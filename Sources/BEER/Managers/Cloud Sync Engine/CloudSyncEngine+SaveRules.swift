import Foundation

extension CloudSyncEngine {
    /// A save rule pinned to a folder in this bottle.
    struct ResolvedSaveRule: Equatable {
        let rule: CloudSaveRule
        /// The folder the rule points at.
        let folder: URL
        /// `rule.path` with placeholders filled in and "/" separators.
        let path: String
    }

    /// A local file a rule matches, and the cloud name Steam would give it.
    struct SaveRuleMatch: Equatable {
        let local: URL
        let remoteName: String
    }

    /// Pin each rule to a folder in this bottle. Drops rules for other
    /// platforms, unknown roots, and placeholders we can't fill in: guessing
    /// there would upload saves under a name Steam never reads back.
    func resolveSaveRules(_ rules: [CloudSaveRule], userHome: URL, installDir: URL?, steamID64: String) -> [ResolvedSaveRule] {
        rules.compactMap { rule in
            guard rule.appliesToWindows,
                  rule.root.uppercased() == "GAMEINSTALL" || steamRootRouting[rule.root.uppercased()] != nil,
                  let path = expandSavePath(rule.path, steamID64: steamID64),
                  let mapped = mapToLocal("%\(rule.root)%/\(path)", userHome: userHome, installDir: installDir)
            else { return nil }
            return ResolvedSaveRule(rule: rule, folder: URL(fileURLWithPath: mapped.path, isDirectory: true), path: path)
        }
    }

    /// Fill in Steam's account placeholders. Nil when the path needs an ID we
    /// don't have, or holds a placeholder we don't know.
    func expandSavePath(_ path: String, steamID64: String) -> String? {
        var expanded = path.replacingOccurrences(of: "\\", with: "/")
        if expanded.contains("{") {
            guard let id = UInt64(steamID64), id != 0 else { return nil }
            expanded = expanded
                .replacingOccurrences(of: "{64BitSteamID}", with: String(id), options: .caseInsensitive)
                .replacingOccurrences(of: "{Steam3AccountID}", with: String(id & 0xFFFF_FFFF), options: .caseInsensitive)
            if expanded.contains("{") { return nil }
        }
        return expanded.split(separator: "/").joined(separator: "/")
    }

    /// Every file under the rule's folder that its pattern matches. Windows
    /// filenames are case-insensitive, so the match is too.
    func matches(of resolved: ResolvedSaveRule) -> [SaveRuleMatch] {
        let fm = FileManager.default
        let folder = resolved.folder
        let files: [URL]
        if resolved.rule.recursive {
            let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            files = (walker?.allObjects as? [URL]) ?? []
        } else {
            files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        }
        let prefix = "%\(resolved.rule.root)%"
        // The walker may hand back symlink-resolved paths (/private/var/… for
        // /var/…), so measure from the resolved folder and rebuild each file
        // under `folder`, where the cloud files' local paths point.
        let resolvedDepth = folder.resolvingSymlinksInPath().pathComponents.count
        return files.compactMap { file in
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  fnmatch(resolved.rule.pattern, file.lastPathComponent, FNM_CASEFOLD) == 0
            else { return nil }
            let relative = file.resolvingSymlinksInPath().pathComponents.dropFirst(resolvedDepth).joined(separator: "/")
            let name = [prefix, resolved.path, relative].filter { !$0.isEmpty }.joined(separator: "/")
            return SaveRuleMatch(local: appendingComponents(relative, to: folder, isDir: false), remoteName: name)
        }
    }

    /// Rule folders worth snapshotting and fingerprinting. A rule with no path
    /// points at a whole root (the install folder, Documents), which is far too
    /// much to copy before every sync. Kept even before the game creates them,
    /// so the first save written there counts as a change worth pushing.
    func saveFoldersToTrack(_ resolved: [ResolvedSaveRule]) -> Set<URL> {
        Set(resolved.filter { !$0.path.isEmpty }.map(\.folder))
    }

    /// Drop folders that sit inside another folder in the set, so a snapshot
    /// doesn't copy the same saves twice.
    func outermostFolders(_ dirs: Set<URL>) -> Set<URL> {
        dirs.filter { dir in
            !dirs.contains { other in
                other != dir && dir.pathComponents.starts(with: other.pathComponents)
            }
        }
    }
}
