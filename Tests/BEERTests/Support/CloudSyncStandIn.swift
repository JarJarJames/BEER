import Foundation
@testable import BEER

/// Runs in place of the CloudSync helper so tests can drive a whole sync
/// without Steam. It answers `enumerate` and `batch` from what the test sets
/// here, writes the files it "downloads", and records every call it gets, so
/// a test can check what reached Steam and in what order.
@MainActor
final class CloudSyncStandIn {
    /// One run of the helper.
    struct Call {
        let command: String
        let downloads: [(filename: String, out: String)]
        let uploads: [(filename: String, mtime: Date)]
    }

    /// What Steam lists for the game.
    var files: [CloudRemoteFile] = [] { didSet { save() } }
    /// What each cloud file holds when downloaded. A file missing here fails.
    var contents: [String: String] = [:] { didSet { save() } }
    /// Cloud files Steam refuses to take.
    var rejectedUploads: Set<String> = [] { didSet { save() } }
    /// What `installsize` reports for the game; nil is Steam listing no size.
    var installBytes: Int64? { didSet { save() } }
    /// Answer every command as Steam does for a revoked sign-in.
    var signInExpired = false { didSet { save() } }

    private let directory: URL
    private var script: URL { directory.appendingPathComponent("CloudSync") }

    var client: CloudSyncClient { CloudSyncClient(binary: script) }

    init(in directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.source.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        save()
    }

    /// Every call so far, oldest first.
    func calls() -> [Call] {
        let log = (try? String(contentsOf: directory.appendingPathComponent("calls.jsonl"), encoding: .utf8)) ?? ""
        return log.split(separator: "\n").compactMap { line in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
            let downloads = (obj["downloads"] as? [[String: Any]] ?? []).map {
                (filename: $0["filename"] as? String ?? "", out: $0["out"] as? String ?? "")
            }
            let uploads = (obj["uploads"] as? [[String: Any]] ?? []).map {
                (filename: $0["filename"] as? String ?? "",
                 mtime: Date(timeIntervalSince1970: ($0["mtime"] as? NSNumber)?.doubleValue ?? 0))
            }
            return Call(command: obj["cmd"] as? String ?? "", downloads: downloads, uploads: uploads)
        }
    }

    private func save() {
        let config: [String: Any] = [
            "files": files.map {
                ["filename": $0.filename, "size": $0.size, "timestamp": $0.timestamp.timeIntervalSince1970, "sha": $0.sha]
            },
            "contents": contents,
            "rejectedUploads": Array(rejectedUploads),
            "signInExpired": signInExpired,
            "installBytes": installBytes.map { $0 as Any } ?? NSNull(),
        ]
        // A test that can't set up its stand-in can't mean anything.
        try! JSONSerialization.data(withJSONObject: config).write(to: directory.appendingPathComponent("standin.json"))
    }

    private static let source = #"""
    #!/usr/bin/python3
    # Stand-in for Tools/CloudSync, written by CloudSyncStandIn.swift.
    import json, os, sys

    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "standin.json")) as f:
        config = json.load(f)
    args = sys.argv[1:]
    cmd = args[0]

    def emit(obj):
        print(json.dumps(obj), flush=True)

    call = {"cmd": cmd}
    if cmd == "batch":
        with open(args[args.index("--jobs") + 1]) as f:
            jobs = json.load(f)
        call["downloads"] = jobs.get("downloads", [])
        call["uploads"] = jobs.get("uploads", [])
    with open(os.path.join(here, "calls.jsonl"), "a") as log:
        log.write(json.dumps(call) + "\n")

    if config["signInExpired"]:
        emit({"error": "InvalidPassword", "auth_failed": True})
        sys.exit(1)
    if cmd == "enumerate":
        emit({"files": config["files"], "savefiles": []})
    elif cmd == "installsize":
        emit({"bytes": config["installBytes"]})
    elif cmd == "batch":
        for d in call["downloads"]:
            content = config["contents"].get(d["filename"])
            if content is None:
                emit({"op": "download", "filename": d["filename"], "error": "File not found"})
                continue
            os.makedirs(os.path.dirname(d["out"]), exist_ok=True)
            with open(d["out"], "w") as f:
                f.write(content)
            emit({"op": "download", "filename": d["filename"], "ok": True})
        for u in call["uploads"]:
            if u["filename"] in config["rejectedUploads"]:
                emit({"op": "upload", "filename": u["filename"], "error": "Steam refused the upload"})
            else:
                emit({"op": "upload", "filename": u["filename"], "ok": True})
        emit({"summary": True})
    else:
        emit({"error": "the stand-in doesn't answer " + cmd})
        sys.exit(1)
    """#
}
