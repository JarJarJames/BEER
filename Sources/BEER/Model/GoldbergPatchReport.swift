import AchievementUI
import Foundation

struct GoldbergPatchReport {
    var patched: [URL]      // .dll paths we replaced
    var backedUp: [URL]     // matching .original paths
    var settingsDirs: [URL] // steam_settings folders we created
    var alreadyPatched: Int // count of DLLs we found but had already swapped

    var totalPatched: Int { patched.count + alreadyPatched }
}
