// Publishes the pad's D-pad as a HID hat value for the in-bottle hid shim.
//
// Wine's winexinput.sys reads a D-pad only from a source hat switch (usage
// 0x39) and skips button usages above 10, so a pad that reports its D-pad as
// buttons 12-15 with no hat loses it inside the driver, before anything in the
// bottle can see it. We read those buttons here, where they still exist.
//
// The bit offsets below were measured against one specific report layout, so
// the helper only attaches to a device whose HID report descriptor hashes to
// the fingerprint BEER passes in. A pad with the same vendor/product but a
// different descriptor is left alone and logged, never guessed at.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <CommonCrypto/CommonDigest.h>
#include <IOKit/hid/IOHIDManager.h>

enum { BTN_BACK = 7, BTN_START = 8, BTN_L3 = 9, BTN_R3 = 10,
       DPAD_UP = 12, DPAD_DOWN = 13, DPAD_LEFT = 14, DPAD_RIGHT = 15 };

static const char *g_path;
static const char *g_fingerprint;
static IOHIDDeviceRef g_device;
static unsigned short g_vid, g_pid;
static int g_up, g_down, g_left, g_right;
static int g_back, g_start, g_l3, g_r3;
static unsigned char g_last[8] = { 0xff };
static int g_verbose;

static unsigned char to_hat(void)
{
    if (g_up && g_right) return 2;
    if (g_down && g_right) return 4;
    if (g_down && g_left) return 6;
    if (g_up && g_left) return 8;
    if (g_up) return 1;
    if (g_right) return 3;
    if (g_down) return 5;
    if (g_left) return 7;
    return 0;
}

// Wine assigns a HID item's usages in ascending order rather than declaration
// order, so a descriptor that declares a group as {9,10,7,8} — as this pad does
// — reaches the bottle with Back/Start and L3/R3 swapped. We read those four by
// usage here, where the association is correct, and the shim substitutes them.
static unsigned char to_buttons(void)
{
    return (unsigned char)((g_back  ? 1 : 0)
                         | (g_start ? 2 : 0)
                         | (g_l3    ? 4 : 0)
                         | (g_r3    ? 8 : 0));
}

// Layout shared with hid_shim.c's `struct pad_state`:
//   [0] hat  [1] Back/Start/L3/R3 mask  [2] pad attached  [3] 0
//   [4..5] vendor  [6..7] product (little-endian)
// The shim only touches the in-bottle device with this vendor/product, and
// only while [2] is set.
static void publish(void)
{
    unsigned char state[8] = {
        to_hat(), to_buttons(), g_device ? 1 : 0, 0,
        g_vid & 0xff, g_vid >> 8, g_pid & 0xff, g_pid >> 8
    };
    if (memcmp(state, g_last, sizeof(state)) == 0) return;
    memcpy(g_last, state, sizeof(state));

    // Write-then-rename so the shim never reads a half-written state.
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s.tmp", g_path);
    FILE *f = fopen(tmp, "wb");
    if (!f) return;
    fwrite(state, 1, sizeof(state), f);
    fclose(f);
    rename(tmp, g_path);

    if (g_verbose) {
        fprintf(stderr, "[pad] hat=%u buttons=0x%x%s%s%s%s\n", state[0], state[1],
                g_back?" BACK":"", g_start?" START":"", g_l3?" L3":"", g_r3?" R3":"");
        fflush(stderr);
    }
}

// The report's button bits, in the order the descriptor declares them:
//
//   byte 2: bit0..3 = D-pad up, down, left, right
//           bit4..7 = Start, Back, L3, R3
//
// The descriptor declares that second group as usages 9,10,7,8, and macOS's
// usage-matching API hands them out ascending (7,8,9,10) instead. Neither
// ordering matches the hardware: the bits were verified against real presses,
// and that is what this decode follows. Reading the raw bits also sidesteps the
// usage-matching mismatch entirely, which is what already made the D-pad work.
static void report_cb(void *ctx, IOReturn res, void *sender, IOHIDReportType type,
                      uint32_t id, uint8_t *report, CFIndex len)
{
    (void)ctx; (void)res; (void)sender; (void)type; (void)id;
    if (len < 3 || !g_device) return;

    uint8_t b = report[2];
    g_up    = (b >> 0) & 1;
    g_down  = (b >> 1) & 1;
    g_left  = (b >> 2) & 1;
    g_right = (b >> 3) & 1;
    g_start = (b >> 4) & 1;
    g_back  = (b >> 5) & 1;
    g_l3    = (b >> 6) & 1;
    g_r3    = (b >> 7) & 1;

    publish();
}

// SHA-256 of the device's HID report descriptor, as lowercase hex.
static int descriptor_fingerprint(IOHIDDeviceRef dev, char out[CC_SHA256_DIGEST_LENGTH * 2 + 1])
{
    CFTypeRef value = IOHIDDeviceGetProperty(dev, CFSTR(kIOHIDReportDescriptorKey));
    if (!value || CFGetTypeID(value) != CFDataGetTypeID()) return 0;

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(CFDataGetBytePtr(value), (CC_LONG)CFDataGetLength(value), digest);
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) sprintf(out + i * 2, "%02x", digest[i]);
    return 1;
}

static void clear_buttons(void)
{
    g_up = g_down = g_left = g_right = 0;
    g_back = g_start = g_l3 = g_r3 = 0;
}

static void matched(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef dev)
{
    (void)ctx; (void)res; (void)sender;
    static uint8_t buf[64];

    char fingerprint[CC_SHA256_DIGEST_LENGTH * 2 + 1];
    if (!descriptor_fingerprint(dev, fingerprint) || strcmp(fingerprint, g_fingerprint) != 0) {
        fprintf(stderr, "[pad] ignoring device: descriptor does not match the measured layout\n");
        fflush(stderr);
        return;
    }
    // One pad feeds the shim at a time; a second identical pad would
    // otherwise overwrite the first's state report by report.
    if (g_device) {
        fprintf(stderr, "[pad] ignoring second matching device\n");
        fflush(stderr);
        return;
    }

    g_device = dev;
    IOHIDDeviceRegisterInputReportCallback(dev, buf, sizeof(buf), report_cb, NULL);
    fprintf(stderr, "[pad] device matched, decoding raw reports\n");
    fflush(stderr);
    publish();
}

static void removed(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef dev)
{
    (void)ctx; (void)res; (void)sender;
    if (dev != g_device) return;
    g_device = NULL;
    clear_buttons();
    publish();
    fprintf(stderr, "[pad] device removed\n");
    fflush(stderr);
}

// Leave a neutral, detached state behind so nothing reads a press that was
// held when the helper stopped.
static void shut_down(void)
{
    g_device = NULL;
    clear_buttons();
    publish();
    exit(0);
}

int main(int argc, char **argv)
{
    if (argc < 5) {
        fprintf(stderr, "usage: dpad_helper <vid> <pid> <descriptor sha256> <outfile> [-v]\n");
        return 2;
    }
    long vid = strtol(argv[1], NULL, 0), pid = strtol(argv[2], NULL, 0);
    g_vid = (unsigned short)vid;
    g_pid = (unsigned short)pid;
    g_fingerprint = argv[3];
    g_path = argv[4];
    g_verbose = (argc > 5);

    publish();

    // Stopped by BEER when the game exits (SIGTERM), or orphaned if BEER
    // itself goes away — either way, clean up rather than hold the pad open.
    signal(SIGTERM, SIG_IGN);
    signal(SIGINT, SIG_IGN);
    dispatch_source_t term = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    dispatch_source_t intr = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
    dispatch_source_t parent = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)getppid(),
                                                      DISPATCH_PROC_EXIT, dispatch_get_main_queue());
    dispatch_source_set_event_handler(term, ^{ shut_down(); });
    dispatch_source_set_event_handler(intr, ^{ shut_down(); });
    dispatch_source_set_event_handler(parent, ^{ shut_down(); });
    dispatch_resume(term);
    dispatch_resume(intr);
    dispatch_resume(parent);

    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    CFMutableDictionaryRef m = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFNumberRef v = CFNumberCreate(kCFAllocatorDefault, kCFNumberLongType, &vid);
    CFNumberRef p = CFNumberCreate(kCFAllocatorDefault, kCFNumberLongType, &pid);
    CFDictionarySetValue(m, CFSTR(kIOHIDVendorIDKey), v);
    CFDictionarySetValue(m, CFSTR(kIOHIDProductIDKey), p);
    IOHIDManagerSetDeviceMatching(mgr, m);
    IOHIDManagerRegisterDeviceMatchingCallback(mgr, matched, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(mgr, removed, NULL);
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    if (IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
        fprintf(stderr, "[dpad] IOHIDManagerOpen failed\n");
        return 1;
    }
    fprintf(stderr, "[dpad] watching %04lx:%04lx -> %s\n", vid, pid, g_path);
    fflush(stderr);
    CFRunLoopRun();
    return 0;
}
