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
  bits still exist and publishes its state to `drive_c/beer_dpad.bin` in the
  bottle: hat value, Back/Start/L3/R3 mask, whether the pad is attached, and
  the pad's vendor/product.
- `hid_shim.c` — built as `hid.dll` for the bottle. Forwards every export to a
  copy of Wine's own `hid.dll` renamed `hid_orig.dll`, and intercepts
  `HidP_GetUsageValue` (fills the empty hat, mirrors the Y axes),
  `HidP_GetUsages` (substitutes the four mislabelled buttons), and
  `HidD_GetPreparsedData`/`HidD_FreePreparsedData` (to know which device each
  call is about).

Both files must be installed together: `hid.dll` without `hid_orig.dll` beside
it aborts on the first forwarded call.

## When it applies

Automatically, per launch, and only when the evidence says it should:

1. **BEER matches the pad by its descriptor.** The helper's bit offsets were
   measured against one report layout, so BEER compares each connected pad's
   HID report descriptor (read from IOHID without opening the device) against
   the SHA-256 fingerprints in `ControllerFixProfiles`. Vendor/product alone
   is not enough: the same IDs with a different layout is not applied to. No
   match means no shim, no helper, and a log line naming what was connected.
2. **The helper only reads that pad.** It re-checks the fingerprint itself,
   follows the pad across disconnects, and on exit (game over, or BEER gone)
   leaves a neutral, detached state behind.
3. **The shim only touches that pad.** `winexinput.sys` passes attribute
   queries through to the source device, so `HidD_GetAttributes` on the device
   the game reads still reports the source pad's vendor/product. The shim
   records which preparsed data belongs to the helper's pad and changes values
   only for that device, and only while the helper reports it attached. Any
   other controller is passed through unchanged.

There is no setting. Every decision is logged for the launch: what was
connected, whether it matched, and the shim's "D-pad path is live" once the
game reads the hat.

## Building

```bash
./build.sh            # installs into Application Support, for `swift run`
./build.sh <out-dir>  # what scripts/build_app.sh uses to bundle it
```

`hid.dll` needs `mingw-w64`. Its forward list, `hid.def`, is checked in; Wine's
`hid.dll` exports the same names across every runtime BEER installs. If one
ever differs, regenerate it with `gen_def.py <runtime hid.dll> > hid.def`.

## Adding a pad

Measure its reports against real presses first, the way the Steam pad's were,
then add its vendor/product and descriptor fingerprint to
`ControllerFixProfiles`. An unmeasured pad is left alone by design.

## Status

The decode was verified end to end against Kingdom Come: Deliverance II on
GPTK-4.0-cx26 with a 2026 Steam Controller (Steam's virtual pad, `045e:028e`),
when the fix was a manual per-game switch. The automatic gating described above
needs the same run repeated.

`BEER_MENU_BUTTON_REMAP` / `BEER_INVERT_STICK_Y` in `hid_shim.c` remain as
escape hatches.
