import Foundation

extension CloudSyncEngine {
    struct UploadPlan {
        var uploads: [CloudSyncClient.UploadJob] = []
        var skipped = 0
        var failures: [(filename: String, reason: String)] = []
    }

    /// Decide which local saves to push: those strictly newer than their cloud
    /// copy, and those with no cloud copy yet.
    ///
    /// Saves are found in folders that already have cloud files, and in the
    /// folders the game's save rules name. The rules are what find a game's
    /// first saves, or a new save folder, which have no cloud files to point
    /// at them.
    func planUploads(remote: [CloudRemoteFile], cloudDirs: Set<URL>, ruleMatches: [SaveRuleMatch],
                     userHome: URL, installDir: URL?) -> UploadPlan {
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
            for fileURL in entries where (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                candidates[fileURL.path] = (fileURL, nil)
            }
        }
        for match in ruleMatches where candidates[match.local.path]?.ruleName == nil {
            candidates[match.local.path] = (match.local, match.remoteName)
        }

        for path in candidates.keys.sorted() {
            let (fileURL, ruleName) = candidates[path]!
            guard let localMTime = fileMTime(fileURL) else { continue }

            let remoteName: String
            if let existing = remoteByLocalPath[path] {
                if localMTime <= existing.timestamp.addingTimeInterval(2) { plan.skipped += 1; continue }
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
            plan.uploads.append(.init(filename: remoteName, local: fileURL, mtime: localMTime))
        }
        return plan
    }
}
