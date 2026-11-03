import Foundation

extension CloudSyncEngine {
    struct UploadPlan {
        var uploads: [CloudSyncClient.UploadJob] = []
        var skipped = 0
        var failures: [(filename: String, reason: String)] = []
    }

    /// Decide which local saves to push: those strictly newer than their cloud
    /// copy, and those with no cloud copy yet. Saves under `forcing` (restored
    /// ones the player chose to keep) go up whenever they differ, however old.
    ///
    /// Saves are found in folders that already have cloud files, and in the
    /// folders the game's save rules name. The rules are what find a game's
    /// first saves, or a new save folder, which have no cloud files to point
    /// at them.
    func planUploads(remote: [CloudRemoteFile], cloudDirs: Set<URL>, ruleMatches: [SaveRuleMatch],
                     userHome: URL, installDir: URL?, forcing: [URL] = []) -> UploadPlan {
        var plan = UploadPlan()
        var remoteByLocalPath: [String: CloudRemoteFile] = [:]
        // Learn the remote directory convention from existing cloud files:
        // local-dir → remote-dir-prefix (filename minus its last component).
        // Steam's own names win over ones built from a rule.
        var remoteDirByLocalDir: [String: String] = [:]
        for rf in remote {
            guard let local = mapToLocal(rf.filename, userHome: userHome, installDir: installDir) else { continue }
            if remoteByLocalPath[local.path] == nil { remoteByLocalPath[local.path] = rf }
            remoteDirByLocalDir[local.deletingLastPathComponent().path] = remoteDir(of: rf.filename)
        }

        var candidates: [String: (url: URL, ruleName: String?)] = [:]
        for dir in cloudDirs {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries where (try? entry.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                // The listing hands back link-resolved paths: a bottle's
                // Documents is a link to the Mac's own, so a save there comes
                // back under /Users/…/Documents. Rebuild it under `dir`, where
                // the cloud files' local paths point.
                let fileURL = dir.appendingPathComponent(entry.lastPathComponent, isDirectory: false)
                candidates[fileURL.path] = (fileURL, nil)
            }
        }
        for match in ruleMatches where candidates[match.local.path]?.ruleName == nil {
            candidates[match.local.path] = (match.local, match.remoteName)
        }

        for path in candidates.keys.sorted() {
            let (fileURL, ruleName) = candidates[path]!
            guard let localMTime = fileMTime(fileURL) else { continue }
            let forced = forcing.contains { Self.isInside(fileURL, $0) }

            let remoteName: String
            if let existing = remoteByLocalPath[path] {
                if !forced, localMTime <= existing.timestamp.addingTimeInterval(2) { plan.skipped += 1; continue }
                if localFileMatchesRemote(fileURL, remote: existing) {
                    plan.skipped += 1; continue
                }
                remoteName = existing.filename
            } else if let prefix = remoteDirByLocalDir[fileURL.deletingLastPathComponent().path] {
                remoteName = prefix.isEmpty ? fileURL.lastPathComponent : "\(prefix)/\(fileURL.lastPathComponent)"
            } else if let ruleName {
                remoteName = ruleName
            } else {
                plan.failures.append((fileURL.lastPathComponent, "couldn't infer cloud path"))
                continue
            }
            // A kept restore goes up stamped now. Under its old date, Steam on
            // another PC would see its own copy as newer and put it back.
            plan.uploads.append(.init(filename: remoteName, local: fileURL, mtime: forced ? Date() : localMTime))
        }
        return plan
    }
}
