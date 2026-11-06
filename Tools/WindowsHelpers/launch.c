// beer_launch.exe: starts a game's launcher with beer_launch_hook.dll in it.
//
// Some launchers start the game's real exe themselves (Fallout4Launcher.exe
// starts Fallout4.exe). That exe is wrapped in SteamStub and only gets past it
// when gbe_fork's loader starts it, so the hook makes the launcher start the
// loader instead (see launch_hook.c). gbe_fork's loader can't wrap the
// launcher itself: when the launcher exits it puts Steam's registry entries
// back, out from under the game it just started.
//
// Reads `launch=` from beer_launch.txt beside it: the launcher, relative to
// this exe's folder. Starts it suspended in its own folder, loads the hook into
// it, lets it run and waits for it, passing on its arguments and exit code. If
// the hook can't be loaded the launcher still runs, as it would without BEER.
//
// Built by scripts/build_windows_helpers.sh with mingw-w64.

#include "helpers.h"

// The command line after this exe's own name.
static const WCHAR *arguments(const WCHAR *command_line)
{
    const WCHAR *c = command_line;
    if (*c == L'"') {
        for (c++; *c && *c != L'"'; c++) {}
        if (*c) c++;
    } else {
        while (*c && *c != L' ' && *c != L'\t') c++;
    }
    while (*c == L' ' || *c == L'\t') c++;
    return c;
}

static BOOL load_into(HANDLE process, const WCHAR *dll)
{
    SIZE_T size = (lstrlenW(dll) + 1) * sizeof(WCHAR);
    void *remote = VirtualAllocEx(process, NULL, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remote) return FALSE;
    BOOL ok = FALSE;
    // kernel32 sits at the same address in every process of the session.
    FARPROC load_library = GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "LoadLibraryW");
    if (WriteProcessMemory(process, remote, dll, size, NULL)) {
        HANDLE thread = CreateRemoteThread(process, NULL, 0, (LPTHREAD_START_ROUTINE)load_library, remote, 0, NULL);
        if (thread) {
            DWORD loaded = 0;
            ok = WaitForSingleObject(thread, 60 * 1000) == WAIT_OBJECT_0
                && GetExitCodeThread(thread, &loaded) && loaded != 0;
            CloseHandle(thread);
        }
    }
    VirtualFreeEx(process, remote, 0, MEM_RELEASE);
    return ok;
}

static DWORD run(void)
{
    WCHAR folder[MAX_PATH], config[MAX_PATH], relative[MAX_PATH], launcher[MAX_PATH], hook[MAX_PATH];
    if (!module_folder(NULL, folder)) return 1;
    lstrcpyW(config, folder);
    lstrcatW(config, L"beer_launch.txt");
    if (!config_value(config, "launch", relative, MAX_PATH) || !resolve(folder, relative, launcher)) return 1;
    lstrcpyW(hook, folder);
    lstrcatW(hook, L"beer_launch_hook.dll");

    WCHAR launcher_folder[MAX_PATH];
    lstrcpyW(launcher_folder, launcher);
    if (!folder_of(launcher_folder)) return 1;

    const WCHAR *passed = arguments(GetCommandLineW());
    int length = lstrlenW(launcher) + lstrlenW(passed) + 4;
    WCHAR *command_line = HeapAlloc(GetProcessHeap(), 0, length * sizeof(WCHAR));
    if (!command_line) return 1;
    wsprintfW(command_line, L"\"%s\" %s", launcher, passed);

    STARTUPINFOW startup = { .cb = sizeof startup };
    PROCESS_INFORMATION process;
    if (!CreateProcessW(launcher, command_line, NULL, NULL, FALSE, CREATE_SUSPENDED, NULL,
                        launcher_folder, &startup, &process))
        return 1;
    load_into(process.hProcess, hook);
    ResumeThread(process.hThread);
    WaitForSingleObject(process.hProcess, INFINITE);

    DWORD code = 0;
    GetExitCodeProcess(process.hProcess, &code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return code;
}

void start(void)
{
    ExitProcess(run());
}
