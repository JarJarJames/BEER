// hid.dll shim: restores the D-pad that Wine's winexinput.sys discards.
//
// winexinput.sys builds the pad it exposes by reading a hat switch (usage 0x39)
// from the source device and skipping every button usage above 10. Pads that
// report the D-pad as buttons 12-15 with no hat — Steam's virtual gamepad among
// them — therefore lose the D-pad inside the driver, before anything in the
// bottle can read it. The exposed device still *declares* a hat switch; it is
// simply never populated.
//
// So: a macOS-side helper reads the D-pad where the bits still exist and
// publishes a hat value; this shim fills it into the hat the game already reads.
// Every other hid.dll entry point forwards straight to the builtin.
//
// Only the pad the helper matched is touched. winexinput.sys passes attribute
// queries through to the source device, so HidD_GetAttributes on the device
// the game reads still reports the source pad's vendor and product. We note
// which preparsed data belongs to that pad when the game asks for it, and every
// other device — a second, real controller included — passes through as-is.
#include <windows.h>
#include <stdio.h>

#define HIDP_STATUS_SUCCESS ((NTSTATUS)0x00110000)
#define HID_USAGE_PAGE_GENERIC 0x01
#define HID_USAGE_GENERIC_HATSWITCH 0x39
#define HID_USAGE_GENERIC_Y 0x31
#define HID_USAGE_GENERIC_RY 0x34
#define HID_USAGE_PAGE_BUTTON 0x09
#define MAX_TRACKED 32

typedef LONG NTSTATUS;
typedef USHORT USAGE;
typedef USAGE *PUSAGE;
typedef struct { ULONG Size; USHORT VendorID; USHORT ProductID; USHORT VersionNumber; } HID_ATTRS;
typedef NTSTATUS (WINAPI *PFN_GETUSAGEVALUE)(int, USAGE, USHORT, USAGE, PULONG, PVOID, PCHAR, ULONG);
typedef NTSTATUS (WINAPI *PFN_GETUSAGES)(int, USAGE, USHORT, PUSAGE, PULONG, PVOID, PCHAR, ULONG);
typedef BOOLEAN (WINAPI *PFN_GETPREPARSED)(HANDLE, PVOID *);
typedef BOOLEAN (WINAPI *PFN_FREEPREPARSED)(PVOID);
typedef BOOLEAN (WINAPI *PFN_GETATTRIBUTES)(HANDLE, HID_ATTRS *);

static PFN_GETUSAGEVALUE real_GetUsageValue;
static PFN_GETUSAGES real_GetUsages;
static PFN_GETPREPARSED real_GetPreparsedData;
static PFN_FREEPREPARSED real_FreePreparsedData;
static PFN_GETATTRIBUTES real_GetAttributes;
static CRITICAL_SECTION lock;
static char hat_path[MAX_PATH];
static BOOL invert_y = TRUE;
static BOOL menu_remap = FALSE;

/* Preparsed data handed out to the game, with the vendor/product it belongs to. */
static struct { PVOID preparsed; USHORT vid, pid; } tracked[MAX_TRACKED];

/* What the helper publishes — must match dpad_helper.c's layout. */
struct pad_state {
    unsigned char hat;      /* 0 centred, 1..8 */
    unsigned char buttons;  /* Back/Start/L3/R3 bitmask */
    unsigned char present;  /* 1 while the matched pad is attached */
    unsigned char reserved;
    USHORT vid, pid;        /* the pad the helper matched */
};

static void cached_state(struct pad_state *out)
{
    static struct pad_state value;
    static DWORD last_tick;

    DWORD now = GetTickCount();
    EnterCriticalSection(&lock);
    if (now - last_tick >= 4) {          /* ~250 Hz is well past what a D-pad needs */
        last_tick = now;
        HANDLE f = CreateFileA(hat_path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                               NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        struct pad_state s;
        DWORD read = 0;
        if (f == INVALID_HANDLE_VALUE) {
            memset(&value, 0, sizeof(value));    /* no helper, no fix */
        } else {
            if (ReadFile(f, &s, sizeof(s), &read, NULL) && read == sizeof(s) && s.hat <= 8)
                value = s;
            CloseHandle(f);
        }
    }
    *out = value;
    LeaveCriticalSection(&lock);
}

/* The helper's state, if `preparsed` belongs to the pad it is reading. */
static BOOL state_for(PVOID preparsed, struct pad_state *state)
{
    cached_state(state);
    if (!state->present || !preparsed) return FALSE;

    BOOL match = FALSE;
    EnterCriticalSection(&lock);
    for (int i = 0; i < MAX_TRACKED; i++) {
        if (tracked[i].preparsed != preparsed) continue;
        match = tracked[i].vid == state->vid && tracked[i].pid == state->pid;
        break;
    }
    LeaveCriticalSection(&lock);
    return match;
}

__declspec(dllexport) BOOLEAN WINAPI HidD_GetPreparsedData(HANDLE device, PVOID *preparsed)
{
    if (!real_GetPreparsedData) return FALSE;
    BOOLEAN ok = real_GetPreparsedData(device, preparsed);
    if (!ok || !preparsed || !*preparsed) return ok;

    HID_ATTRS attrs = { sizeof(attrs) };
    if (!real_GetAttributes || !real_GetAttributes(device, &attrs)) return ok;

    EnterCriticalSection(&lock);
    for (int i = 0; i < MAX_TRACKED; i++) {
        if (tracked[i].preparsed) continue;
        tracked[i].preparsed = *preparsed;
        tracked[i].vid = attrs.VendorID;
        tracked[i].pid = attrs.ProductID;
        break;
    }
    LeaveCriticalSection(&lock);
    return ok;
}

__declspec(dllexport) BOOLEAN WINAPI HidD_FreePreparsedData(PVOID preparsed)
{
    EnterCriticalSection(&lock);
    for (int i = 0; i < MAX_TRACKED; i++)
        if (tracked[i].preparsed == preparsed) tracked[i].preparsed = NULL;
    LeaveCriticalSection(&lock);
    return real_FreePreparsedData ? real_FreePreparsedData(preparsed) : FALSE;
}

__declspec(dllexport) NTSTATUS WINAPI HidP_GetUsageValue(int type, USAGE page, USHORT collection,
    USAGE usage, PULONG value, PVOID preparsed, PCHAR report, ULONG length)
{
    NTSTATUS status = real_GetUsageValue
        ? real_GetUsageValue(type, page, collection, usage, value, preparsed, report, length)
        : (NTSTATUS)0xC0110000;

    if (type != 0 || !value) return status;

    struct pad_state state;
    if (!state_for(preparsed, &state)) return status;

    /* Steam's virtual pad reports Y in XInput's convention (up = positive)
     * inside a HID descriptor, where HID's convention is the opposite. Games
     * reading the HID axes directly therefore see both sticks inverted.
     * The axes here are 16-bit unsigned, so mirroring about the range works. */
    if (invert_y && status == HIDP_STATUS_SUCCESS && page == HID_USAGE_PAGE_GENERIC
        && (usage == HID_USAGE_GENERIC_Y || usage == HID_USAGE_GENERIC_RY)
        && *value <= 0xffff) {
        *value = 0xffffu - *value;
        return HIDP_STATUS_SUCCESS;
    }

    /* The hat the driver left empty is ours to fill. */
    if (page == HID_USAGE_PAGE_GENERIC && usage == HID_USAGE_GENERIC_HATSWITCH) {
        static LONG announced;
        if (!InterlockedExchange(&announced, 1)) {
            fprintf(stderr, "[hid-shim] game is reading the hat switch - D-pad path is live\n");
            fflush(stderr);
        }
        *value = state.hat;
        return HIDP_STATUS_SUCCESS;
    }
    return status;
}

__declspec(dllexport) NTSTATUS WINAPI HidP_GetUsages(int type, USAGE page, USHORT collection,
    PUSAGE list, PULONG length, PVOID preparsed, PCHAR report, ULONG report_length)
{
    ULONG capacity = length ? *length : 0;
    NTSTATUS status = real_GetUsages
        ? real_GetUsages(type, page, collection, list, length, preparsed, report, report_length)
        : (NTSTATUS)0xC0110000;

    if (type != 0 || page != HID_USAGE_PAGE_BUTTON || status != HIDP_STATUS_SUCCESS
        || !list || !length)
        return status;

    struct pad_state state;
    if (!state_for(preparsed, &state)) return status;

    /* Wine mis-associates usages for items that declare them out of order, which
     * swaps Back/Start with L3/R3 on pads like Steam's virtual gamepad. Drop
     * Wine's version of those four and re-add what the device really reports. */
    ULONG kept = 0;
    for (ULONG i = 0; i < *length; i++) {
        USAGE u = list[i];
        if (u >= 7 && u <= 10) continue;
        list[kept++] = u;
    }

    /* This pad emits L3/R3 for its two menu buttons — confirmed at the macOS
     * HID layer, by usage, before Wine is involved. With the remap on, those
     * become Back/Start so menu buttons work; the cost is that a genuine stick
     * click reports as Back/Start too. BEER_MENU_BUTTON_REMAP=0 turns it off. */
    static const USAGE passthrough[4] = { 7, 8, 9, 10 };
    static const USAGE remap_menu[4]  = { 7, 8, 7, 8 };
    const USAGE *remapped = menu_remap ? remap_menu : passthrough;
    for (int bit = 0; bit < 4; bit++) {
        if (!(state.buttons & (1u << bit))) continue;
        if (kept >= capacity) break;
        USAGE u = remapped[bit];
        BOOL already = FALSE;
        for (ULONG i = 0; i < kept; i++) if (list[i] == u) { already = TRUE; break; }
        if (!already) list[kept++] = u;
    }

    *length = kept;
    return HIDP_STATUS_SUCCESS;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(inst);
        InitializeCriticalSection(&lock);
        char buf[16];
        if (GetEnvironmentVariableA("BEER_INVERT_STICK_Y", buf, sizeof(buf)) && buf[0] == '0')
            invert_y = FALSE;
        if (GetEnvironmentVariableA("BEER_MENU_BUTTON_REMAP", buf, sizeof(buf)) && buf[0] == '1')
            menu_remap = TRUE;
        if (!GetEnvironmentVariableA("BEER_DPAD_FILE", hat_path, sizeof(hat_path)))
            lstrcpynA(hat_path, "C:\\beer_dpad.bin", sizeof(hat_path));
        HMODULE h = LoadLibraryA("hid_orig.dll");
        if (h) {
            real_GetUsageValue = (PFN_GETUSAGEVALUE)GetProcAddress(h, "HidP_GetUsageValue");
            real_GetUsages = (PFN_GETUSAGES)GetProcAddress(h, "HidP_GetUsages");
            real_GetPreparsedData = (PFN_GETPREPARSED)GetProcAddress(h, "HidD_GetPreparsedData");
            real_FreePreparsedData = (PFN_FREEPREPARSED)GetProcAddress(h, "HidD_FreePreparsedData");
            real_GetAttributes = (PFN_GETATTRIBUTES)GetProcAddress(h, "HidD_GetAttributes");
        }
        fprintf(stderr, "[hid-shim] loaded, hat source = %s, builtin = %s, invertY = %s, menuRemap = %s\n",
                hat_path, real_GetPreparsedData ? "ok" : "MISSING", invert_y ? "on" : "off", menu_remap ? "on" : "off");
        fflush(stderr);
    }
    return TRUE;
}
