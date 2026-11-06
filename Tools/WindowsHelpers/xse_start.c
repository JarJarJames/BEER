// beer_xse_start.dll: starts a script extender (F4SE) inside a game BEER
// launches through the Steam emulator's loader.
//
// A script extender's own loader (f4se_loader.exe) starts the game suspended,
// loads f4se_<version>.dll into it and calls that DLL's first export
// (StartF4SE), which hooks the game before it runs. BEER can't use that
// loader: the game's exe is wrapped in SteamStub, and only gbe_fork's loader
// gets it past that check. gbe_fork's loader loads DLLs into the game the same
// way, suspended, but only loads them. This DLL is one of them, loaded after
// the SteamStub patch, and does the rest of what f4se_loader does: load the
// DLL for this game version and call its first export.
//
// Which extender comes from beer_xse_start.txt beside this DLL (prefix=f4se). The
// version comes from the game's exe, as f4se_loader names its DLL:
// <prefix>_<major>_<minor>_<build>.dll beside the exe. No such DLL means this
// F4SE doesn't support this game version, so the game runs without it.
//
// Built by scripts/build_windows_helpers.sh with mingw-w64.

#include "helpers.h"

// `prefix=` from beer_xse_start.txt beside this DLL, letters and digits only:
// it becomes part of a file name.
static BOOL read_prefix(HMODULE self, WCHAR *prefix, int size)
{
    WCHAR config[MAX_PATH];
    if (!module_folder(self, config) || lstrlenW(config) + 32 >= MAX_PATH) return FALSE;
    lstrcatW(config, L"beer_xse_start.txt");
    if (!config_value(config, "prefix", prefix, size)) return FALSE;
    for (WCHAR *c = prefix; *c; c++)
        if (!((*c >= L'a' && *c <= L'z') || (*c >= L'0' && *c <= L'9'))) { *c = 0; break; }
    return prefix[0] != 0;
}

static BOOL game_version(const WCHAR *exe, DWORD *major, DWORD *minor, DWORD *build)
{
    DWORD unused = 0;
    DWORD size = GetFileVersionInfoSizeW(exe, &unused);
    if (!size) return FALSE;
    void *data = HeapAlloc(GetProcessHeap(), 0, size);
    if (!data) return FALSE;
    VS_FIXEDFILEINFO *info = NULL;
    UINT length = 0;
    BOOL ok = GetFileVersionInfoW(exe, 0, size, data)
        && VerQueryValueW(data, L"\\", (void **)&info, &length) && info;
    if (ok) {
        *major = HIWORD(info->dwFileVersionMS);
        *minor = LOWORD(info->dwFileVersionMS);
        *build = HIWORD(info->dwFileVersionLS);
    }
    HeapFree(GetProcessHeap(), 0, data);
    return ok;
}

static void start_extender(HMODULE self)
{
    WCHAR prefix[32];
    if (!read_prefix(self, prefix, 32)) return;

    WCHAR exe[MAX_PATH];
    DWORD major, minor, build;
    if (!GetModuleFileNameW(NULL, exe, MAX_PATH) || !game_version(exe, &major, &minor, &build)) return;
    if (!folder_of(exe)) return;

    WCHAR dll[MAX_PATH];
    if (wsprintfW(dll, L"%s%s_%u_%u_%u.dll", exe, prefix, major, minor, build) <= 0) return;

    HMODULE extender = LoadLibraryW(dll);
    if (!extender) return;
    FARPROC start = GetProcAddress(extender, MAKEINTRESOURCEA(1));
    if (start) ((void (*)(void))start)();
}

BOOL WINAPI DllMain(HINSTANCE self, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(self);
        start_extender(self);
    }
    return TRUE;
}
