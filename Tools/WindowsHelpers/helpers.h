// Shared by BEER's Windows helpers. No C runtime: they're built with
// -nostdlib, so only Windows calls.
#pragma once
#include <windows.h>

// Cut `path` back to its folder, keeping the trailing backslash.
static BOOL folder_of(WCHAR *path)
{
    WCHAR *slash = NULL;
    for (WCHAR *c = path; *c; c++)
        if (*c == L'\\' || *c == L'/') slash = c;
    if (!slash) return FALSE;
    slash[1] = 0;
    return TRUE;
}

// The folder `module` was loaded from (NULL: the process's exe).
static BOOL module_folder(HMODULE module, WCHAR *out)
{
    return GetModuleFileNameW(module, out, MAX_PATH) && folder_of(out);
}

// `value` of the line `key=value` in the UTF-8 file `path`; BEER writes these.
static BOOL config_value(const WCHAR *path, const char *key, WCHAR *out, int size)
{
    char text[4096];
    DWORD read = 0;
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (file == INVALID_HANDLE_VALUE) return FALSE;
    BOOL ok = ReadFile(file, text, sizeof text - 1, &read, NULL);
    CloseHandle(file);
    if (!ok) return FALSE;
    text[read] = 0;

    int key_length = lstrlenA(key);
    for (char *line = text; *line; ) {
        char *end = line;
        while (*end && *end != '\n' && *end != '\r') end++;
        char next = *end;
        *end = 0;
        if (end - line > key_length && line[key_length] == '='
            && CompareStringA(LOCALE_INVARIANT, 0, line, key_length, key, key_length) == CSTR_EQUAL)
            return MultiByteToWideChar(CP_UTF8, 0, line + key_length + 1, -1, out, size) > 0;
        line = next ? end + 1 : end;
    }
    return FALSE;
}

// `relative` made absolute against `folder` (which ends in a backslash).
static BOOL resolve(const WCHAR *folder, const WCHAR *relative, WCHAR *out)
{
    WCHAR joined[MAX_PATH * 2];
    BOOL absolute = relative[0] == L'\\' || (relative[0] && relative[1] == L':');
    if (absolute) lstrcpynW(joined, relative, MAX_PATH * 2);
    else if (lstrlenW(folder) + lstrlenW(relative) < MAX_PATH * 2) { lstrcpyW(joined, folder); lstrcatW(joined, relative); }
    else return FALSE;
    DWORD length = GetFullPathNameW(joined, MAX_PATH, out, NULL);
    return length > 0 && length < MAX_PATH;
}
