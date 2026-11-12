import Foundation
@testable import BEER

/// A fake Steam for tests: a script that runs in place of the CloudSync helper,
/// so tests can drive a whole sync or install check without Steam. It answers
/// `enumerate`, `batch`, `installsize`, `clienticon` and `updatecheck` from what the test sets here, writes
/// the files it "downloads", and records every call it gets, so a test can
/// check what reached Steam and in what order.
@MainActor
final class FakeSteam {
    /// One run of the helper.
    struct Call {
        let command: String
        let downloads: [(filename: String, out: String)]
        let uploads: [(filename: String, mtime: Date)]
        /// The apps an `installsize`, `clienticon` or `updatecheck` call asked about.
        let appIDs: [Int]
        /// The game folders an `updatecheck` call asked about, and each one's left-out depots.
        var directories: [String] = []
        var leftOutDepots: [[Int]] = []
    }

    /// What Steam lists for the game.
    var files: [CloudRemoteFile] = [] { didSet { save() } }
    /// What each cloud file holds when downloaded. A file missing here fails.
    var contents: [String: String] = [:] { didSet { save() } }
    /// Cloud files Steam refuses to take.
    var rejectedUploads: Set<String> = [] { didSet { save() } }
    /// What Steam lists as each app's install size. `installsize` reports the
    /// sum for the apps asked about, or no size when none of them is listed.
    var installSizes: [Int: Int64] = [:] { didSet { save() } }
    /// The depots `installsize` lists for each app, and the owned DLC among them.
    var installDepots: [Int: [Int]] = [:] { didSet { save() } }
    var installDLC: [Int: [InstallableDLC]] = [:] { didSet { save() } }
    /// Each depot's own size, which `installsize` lists as `depotBytes`.
    var installDepotBytes: [Int: Int64] = [:] { didSet { save() } }
    /// The hash of each app's Windows icon. `clienticon` reports none for an app missing here.
    var clientIcons: [Int: String] = [:] { didSet { save() } }
    /// What `updatecheck` reports for each installed game. A game missing here is `unknown`.
    var gameUpdates: [Int: GameUpdateStatus] = [:] { didSet { save() } }
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
            return Call(command: obj["cmd"] as? String ?? "", downloads: downloads, uploads: uploads,
                        appIDs: obj["appids"] as? [Int] ?? [], directories: obj["dirs"] as? [String] ?? [],
                        leftOutDepots: obj["leftout"] as? [[Int]] ?? [])
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
            "installSizes": Dictionary(uniqueKeysWithValues: installSizes.map { (String($0.key), $0.value) }),
            "installDepots": Dictionary(uniqueKeysWithValues: installDepots.map { (String($0.key), $0.value) }),
            "installDepotBytes": Dictionary(uniqueKeysWithValues: installDepotBytes.map { (String($0.key), $0.value) }),
            "installDLC": Dictionary(uniqueKeysWithValues: installDLC.map { app, dlc in
                (String(app), dlc.map { ["appid": $0.appID, "name": $0.name, "bytes": $0.bytes as Any, "depots": $0.depotIDs] })
            }),
            "clientIcons": Dictionary(uniqueKeysWithValues: clientIcons.map { (String($0.key), $0.value) }),
            "gameUpdates": Dictionary(uniqueKeysWithValues: gameUpdates.map { (String($0.key), $0.value.rawValue) }),
        ]
        // A test that can't set up its fake Steam can't mean anything.
        try! JSONSerialization.data(withJSONObject: config).write(to: directory.appendingPathComponent("fakesteam.json"))
    }

    private static let source = #"""
    #!/usr/bin/python3
    # Fake Steam for tests: replaces Tools/CloudSync. Written by FakeSteam.swift.
    import json, os, sys

    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "fakesteam.json")) as f:
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
    if cmd == "installsize":
        call["appids"] = [int(a) for a in args[args.index("--appids") + 1].split(",")]
    if cmd == "clienticon":
        call["appids"] = [int(args[args.index("--appid") + 1])]
    if cmd == "updatecheck":
        with open(args[args.index("--jobs") + 1]) as f:
            jobs = json.load(f)
        call["appids"] = [j["appid"] for j in jobs]
        call["dirs"] = [j["dir"] for j in jobs]
        call["leftout"] = [j.get("leftout", []) for j in jobs]
    with open(os.path.join(here, "calls.jsonl"), "a") as log:
        log.write(json.dumps(call) + "\n")

    if config["signInExpired"]:
        emit({"error": "InvalidPassword", "auth_failed": True})
        sys.exit(1)
    if cmd == "enumerate":
        emit({"files": config["files"], "savefiles": []})
    elif cmd == "installsize":
        sizes = [config["installSizes"][str(a)] for a in call["appids"] if str(a) in config["installSizes"]]
        emit({"bytes": sum(sizes) if sizes else None,
              "depots": [d for a in call["appids"] for d in config["installDepots"].get(str(a), [])],
              "depotBytes": {str(d): config["installDepotBytes"][str(d)]
                             for a in call["appids"] for d in config["installDepots"].get(str(a), [])
                             if str(d) in config["installDepotBytes"]},
              "dlc": [d for a in call["appids"] for d in config["installDLC"].get(str(a), [])]})
    elif cmd == "clienticon":
        emit({"clienticon": config["clientIcons"].get(str(call["appids"][0]))})
    elif cmd == "updatecheck":
        emit({"games": [{"appid": a, "status": config["gameUpdates"].get(str(a), "unknown")} for a in call["appids"]]})
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
        emit({"error": "fake Steam doesn't answer " + cmd})
        sys.exit(1)
    """#
}
