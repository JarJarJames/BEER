// beer_launch_hook.dll: loaded into a game's launcher by beer_launch.exe, it
// sends the launcher's start of the game's exe through gbe_fork's loader.
//
// The launcher starts the game with ShellExecuteW, ShellExecuteExW or
// CreateProcessW from its own exe. This replaces those three in the exe's
// import table. When the file started is named `redirect=` (Fallout4.exe),
// the call starts `to=` (the loader, relative to this DLL's folder) instead,
// with the same arguments; the loader then starts the game where it is, under
// its own name, past SteamStub. Every other call passes through untouched.
//
// Built by scripts/build_windows_helpers.sh with mingw-w64.

#include "helpers.h"
#include <shellapi.h>

static WCHAR redirect_name[MAX_PATH];
static WCHAR redirect_to[MAX_PATH];

static HINSTANCE (WINAPI *real_ShellExecuteW)(HWND, LPCWSTR, LPCWSTR, LPCWSTR, LPCWSTR, INT);
static BOOL (WINAPI *real_ShellExecuteExW)(SHELLEXECUTEINFOW *);
static BOOL (WINAPI *real_CreateProcessW)(LPCWSTR, LPWSTR, LPSECURITY_ATTRIBUTES, LPSECURITY_ATTRIBUTES, BOOL,
                                          DWORD, LPVOID, LPCWSTR, LPSTARTUPINFOW, LPPROCESS_INFORMATION);

// Whether `file` (a path, or a command line's first word) names the game's exe.
static BOOL is_game(const WCHAR *file, int length)
{
    if (!file) return FALSE;
    if (length < 0) length = lstrlenW(file);
    if (length > 0 && file[0] == L'"') { file++; length--; }
    if (length > 0 && file[length - 1] == L'"') length--;
    int start = 0;
    for (int i = 0; i < length; i++)
        if (file[i] == L'\\' || file[i] == L'/') start = i + 1;
    return CompareStringW(LOCALE_INVARIANT, NORM_IGNORECASE, file + start, length - start,
                          redirect_name, -1) == CSTR_EQUAL;
}

static HINSTANCE WINAPI hook_ShellExecuteW(HWND window, LPCWSTR verb, LPCWSTR file, LPCWSTR parameters,
                                           LPCWSTR directory, INT show)
{
    return real_ShellExecuteW(window, verb, is_game(file, -1) ? redirect_to : file, parameters, directory, show);
}

static BOOL WINAPI hook_ShellExecuteExW(SHELLEXECUTEINFOW *info)
{
    if (!info || !is_game(info->lpFile, -1)) return real_ShellExecuteExW(info);
    SHELLEXECUTEINFOW redirected = *info;
    redirected.lpFile = redirect_to;
    BOOL ok = real_ShellExecuteExW(&redirected);
    info->hInstApp = redirected.hInstApp;
    info->hProcess = redirected.hProcess;
    return ok;
}

static BOOL WINAPI hook_CreateProcessW(LPCWSTR application, LPWSTR command_line, LPSECURITY_ATTRIBUTES process_attributes,
                                       LPSECURITY_ATTRIBUTES thread_attributes, BOOL inherit, DWORD flags,
                                       LPVOID environment, LPCWSTR directory, LPSTARTUPINFOW startup,
                                       LPPROCESS_INFORMATION process)
{
    // The command line's first word is the exe; the rest are its arguments.
    const WCHAR *rest = command_line;
    BOOL quoted = rest && *rest == L'"';
    if (rest) {
        if (quoted) { for (rest++; *rest && *rest != L'"'; rest++) {} if (*rest) rest++; }
        else while (*rest && *rest != L' ' && *rest != L'\t') rest++;
    }
    BOOL game = application ? is_game(application, -1)
        : command_line && is_game(command_line, (int)(rest - command_line));
    if (!game)
        return real_CreateProcessW(application, command_line, process_attributes, thread_attributes, inherit,
                                   flags, environment, directory, startup, process);

    int length = lstrlenW(redirect_to) + (rest ? lstrlenW(rest) : 0) + 4;
    WCHAR *redirected = HeapAlloc(GetProcessHeap(), 0, length * sizeof(WCHAR));
    if (!redirected) return FALSE;
    wsprintfW(redirected, L"\"%s\"%s", redirect_to, rest ? rest : L"");
    BOOL ok = real_CreateProcessW(redirect_to, redirected, process_attributes, thread_attributes, inherit, flags,
                                  environment, directory, startup, process);
    HeapFree(GetProcessHeap(), 0, redirected);
    return ok;
}

// Point the exe's import of `dll`!`function` at `hook`, keeping the original.
static void hook_import(const char *dll, const char *function, void *hook, void **original)
{
    BYTE *base = (BYTE *)GetModuleHandleW(NULL);
    IMAGE_NT_HEADERS *headers = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY imports = headers->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (!imports.VirtualAddress) return;
    for (IMAGE_IMPORT_DESCRIPTOR *entry = (IMAGE_IMPORT_DESCRIPTOR *)(base + imports.VirtualAddress); entry->Name; entry++) {
        if (lstrcmpiA((const char *)(base + entry->Name), dll) != 0) continue;
        IMAGE_THUNK_DATA *names = (IMAGE_THUNK_DATA *)(base + (entry->OriginalFirstThunk ? entry->OriginalFirstThunk : entry->FirstThunk));
        IMAGE_THUNK_DATA *addresses = (IMAGE_THUNK_DATA *)(base + entry->FirstThunk);
        for (; names->u1.AddressOfData; names++, addresses++) {
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
            IMAGE_IMPORT_BY_NAME *name = (IMAGE_IMPORT_BY_NAME *)(base + names->u1.AddressOfData);
            if (lstrcmpA((const char *)name->Name, function) != 0) continue;
            DWORD protection;
            if (!VirtualProtect(&addresses->u1.Function, sizeof addresses->u1.Function, PAGE_READWRITE, &protection)) return;
            *original = (void *)addresses->u1.Function;
            addresses->u1.Function = (ULONG_PTR)hook;
            VirtualProtect(&addresses->u1.Function, sizeof addresses->u1.Function, protection, &protection);
        }
    }
}

BOOL WINAPI DllMain(HINSTANCE self, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason != DLL_PROCESS_ATTACH) return TRUE;
    DisableThreadLibraryCalls(self);

    WCHAR folder[MAX_PATH], config[MAX_PATH], relative[MAX_PATH];
    if (!module_folder(self, folder)) return TRUE;
    lstrcpyW(config, folder);
    lstrcatW(config, L"beer_launch.txt");
    if (!config_value(config, "redirect", redirect_name, MAX_PATH)
        || !config_value(config, "to", relative, MAX_PATH) || !resolve(folder, relative, redirect_to))
        return TRUE;

    hook_import("shell32.dll", "ShellExecuteW", (void *)hook_ShellExecuteW, (void **)&real_ShellExecuteW);
    hook_import("shell32.dll", "ShellExecuteExW", (void *)hook_ShellExecuteExW, (void **)&real_ShellExecuteExW);
    hook_import("kernel32.dll", "CreateProcessW", (void *)hook_CreateProcessW, (void **)&real_CreateProcessW);
    return TRUE;
}
