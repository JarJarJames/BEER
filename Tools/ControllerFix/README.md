# Controller Fix

Restores D-pad, stick orientation and menu buttons for pads that reach Wine
through a virtual HID gamepad — Steam Input's among them.

## What's wrong

`winexinput.sys` builds the pad it exposes to the bottle like this:

```c
if (hat < 1 || hat > 8) buttons = 0;           /* source has no hat -> nothing */
else buttons = hat << 10;
for (i = 0; i < count; i++) {
    if (usages[i] < 1 || usages[i] > 10) continue;   /* D-pad usages dropped */
    buttons |= (1 << (usages[i] - 1));
}
```

It reads a D-pad **only** from a source hat switch (usage `0x39`) and discards
button usages above 10. Steam's virtual pad has no hat and reports its D-pad as
buttons 12-15, so the D-pad dies inside the driver — before anything running in
the bottle can see it. The exposed device still *declares* a hat switch; it is
simply never populated.

Two further quirks on the same device, both verified against real presses:

- The sticks report Y in XInput's convention (up = positive) inside a HID
  descriptor, where the convention is the opposite, so games reading the HID
  axes directly see both sticks inverted.
- The report byte holding Start/Back/L3/R3 matches neither its own descriptor
  (which declares usages `9,10,7,8`) nor macOS's usage-matching API (which hands
  them out ascending as `7,8,9,10`). The hardware actually sends
  `Start, Back, L3, R3`. Three orderings for the same four bits — which is why
  every layer downstream mislabels them, and why only measured presses settled
  it.

## How the fix works

Two halves, because the data is destroyed inside the driver:

- `dpad_helper.c` — macOS, IOKit. Reads the pad's raw input reports where the
  bits still exist and publishes two bytes (hat value, button mask) to a file
  inside the bottle.
- `hid_shim.c` — built as `hid.dll` for the bottle. Forwards every export to a
  copy of Wine's own `hid.dll` renamed `hid_orig.dll`, and intercepts only
  `HidP_GetUsageValue` (fills the empty hat, mirrors the Y axes) and
  `HidP_GetUsages` (substitutes the four mislabelled buttons).

Both files must be installed together: `hid.dll` without `hid_orig.dll` beside
it aborts on the first forwarded call.

## Building

```bash
./build.sh /path/to/runtime/lib/wine/x86_64-windows/hid.dll
```

`hid.dll` needs `mingw-w64`. The export list is generated from whichever
runtime's `hid.dll` is passed, so the forwards always match that Wine build.

## Status

Verified end to end against Kingdom Come: Deliverance II on GPTK-4.0-cx26 with a
2026 Steam Controller (Steam's virtual pad, `045e:028e`).

The button bit offsets in `dpad_helper.c` were measured against that pad. They
are almost certainly specific to Steam's virtual gamepad, so a different virtual
pad needs its own verification before this is enabled for it — see
`BEER_MENU_BUTTON_REMAP` / `BEER_INVERT_STICK_Y` in `hid_shim.c` for the escape
hatches.
