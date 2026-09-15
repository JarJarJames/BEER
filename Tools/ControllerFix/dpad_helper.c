// Publishes the pad's D-pad as a HID hat value for the in-bottle hid shim.
//
// Wine's winexinput.sys reads a D-pad only from a source hat switch (usage
// 0x39) and skips button usages above 10, so a pad that reports its D-pad as
// buttons 12-15 with no hat loses it inside the driver, before anything in the
// bottle can see it. We read those buttons here, where they still exist.
//
// Matched by usage rather than by bit offset, so this does not depend on any
// particular report layout.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <IOKit/hid/IOHIDManager.h>

enum { BTN_BACK = 7, BTN_START = 8, BTN_L3 = 9, BTN_R3 = 10,
       DPAD_UP = 12, DPAD_DOWN = 13, DPAD_LEFT = 14, DPAD_RIGHT = 15 };

static const char *g_path;
static int g_up, g_down, g_left, g_right;
static int g_back, g_start, g_l3, g_r3;
static unsigned char g_last_hat = 0xff, g_last_btn = 0xff;
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

static void publish(void)
{
    unsigned char state[2] = { to_hat(), to_buttons() };
    if (state[0] == g_last_hat && state[1] == g_last_btn) return;
    g_last_hat = state[0];
    g_last_btn = state[1];

    FILE *f = fopen(g_path, "wb");
    if (!f) return;
    fwrite(state, 1, sizeof(state), f);
    fclose(f);

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
    if (len < 3) return;

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

static void matched(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef dev)
{
    (void)ctx; (void)res; (void)sender;
    static uint8_t buf[64];
    IOHIDDeviceRegisterInputReportCallback(dev, buf, sizeof(buf), report_cb, NULL);
    fprintf(stderr, "[pad] device matched, decoding raw reports\n");
    fflush(stderr);
}

static void removed(void *ctx, IOReturn res, void *sender, IOHIDDeviceRef dev)
{
    (void)ctx; (void)res; (void)sender; (void)dev;
    g_up = g_down = g_left = g_right = 0;
    g_back = g_start = g_l3 = g_r3 = 0;
    publish();
}

int main(int argc, char **argv)
{
    if (argc < 4) { fprintf(stderr, "usage: dpad_helper <vid> <pid> <outfile> [-v]\n"); return 2; }
    long vid = strtol(argv[1], NULL, 0), pid = strtol(argv[2], NULL, 0);
    g_path = argv[3];
    g_verbose = (argc > 4);

    publish();

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
