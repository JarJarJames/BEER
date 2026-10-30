import Foundation

/// PlayStation pads that Wine's macOS HID bus mishandles: Wine always takes
/// them as raw HID devices (`is_dualshock4_gamepad` / `is_dualsense_gamepad` in
/// winebus), and that bus only builds an XInput device for Xbox pads. So an
/// XInput game sees no controller at all. Wine's SDL bus presents them
/// properly, but drops its copy while the raw one exists.
///
/// When one of these is connected, BEER turns the raw bus off for the launch
/// (`DisableHidraw`) and every pad goes through SDL. The list mirrors Wine's.
enum SDLRoutedGamepads {
    static let identifiers: Set<String> = [
        "054c:05c4", // DualShock 4 [CUH-ZCT1x]
        "054c:09cc", // DualShock 4 [CUH-ZCT2x]
        "054c:0ba0", // DualShock 4 Wireless Adaptor
        "054c:0ce6", // DualSense
        "054c:0df2", // DualSense Edge
    ]
}
