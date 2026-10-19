import Foundation
import Darwin

struct ScanNode: Codable {
    var name: String
    var path: String
    var bytes: Int64 = 0
    var logical_bytes: Int64 = 0
    var files: Int = 0
    var kind = "directory"
    var errors = 0
    var children: [ScanNode]? = nil
    enum CodingKeys: String, CodingKey {
        case name, path, bytes, logical_bytes, files, kind, errors, children
    }
}

extension ScanNode {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? (path as NSString).lastPathComponent
        bytes = try c.decode(Int64.self, forKey: .bytes)
        logical_bytes = try c.decodeIfPresent(Int64.self, forKey: .logical_bytes) ?? bytes
        children = try c.decodeIfPresent([ScanNode].self, forKey: .children)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? (children == nil ? "file" : "directory")
        files = try c.decodeIfPresent(Int.self, forKey: .files) ?? (kind == "file" ? 1 : 0)
        errors = try c.decodeIfPresent(Int.self, forKey: .errors) ?? 0
    }
}

struct Candidate: Codable {
    let path: String
    let bytes: Int64
    let files: Int
    let category: String
    let label: String
    let guidance: String
    let incomplete: Bool
}

struct CleanupRule: Codable {
    let path: String
    let category: String
    let label: String
    let guidance: String
}

struct ScanIssue: Codable {
    let path: String
    let error: String
    let detail: String
}

struct Coverage: Codable {
    let files: Int
    let directories: Int
    let symlinks_skipped: Int
    let mounts_skipped: [String]
    let error_count: Int
    let errors: [ScanIssue]
    let tree_minimum_bytes: Int64
}

struct Volume: Codable {
    let total: Int64
    let used: Int64
    let free: Int64
    let other_shared_usage: Int64
    let free_at_start: Int64
    let source: String
}

struct Snapshot: Codable {
    let version: Int
    let scanned_at: String
    let duration_seconds: Double
    let root: String
    let home: String
    let volume: Volume
    let tree: ScanNode
    let candidates: [Candidate]
    let largest_files: [ScanNode]
    let coverage: Coverage
    let method: [String]
}

enum AssessmentError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}

final class DiskScanner {
    static let dataRoot = "/System/Volumes/Data"
    let root: String
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let minimum: Int64 = 50 * 1024 * 1024
    let cancellation: ScanCancellation
    let progress: (Int, Int, String) -> Void
    private let device: dev_t
    private let rules: [String: CleanupRule]
    private var hardlinks = Set<String>()
    private var issues: [ScanIssue] = []
    private var issueCount = 0
    private var mounts: [String] = []
    private var candidates: [Candidate] = []
    private var largest: [ScanNode] = []
    private var files = 0
    private var directories = 0
    private var symlinks = 0
    private var lastProgress = Date.distantPast

    init(root: String, rulesURL: URL, cancellation: ScanCancellation,
         progress: @escaping (Int, Int, String) -> Void = { _,_,_ in }) throws {
        self.root = (root as NSString).standardizingPath
        self.cancellation = cancellation
        self.progress = progress
        var info = stat()
        guard lstat(self.root, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            throw AssessmentError.message("Choose an existing folder, rather than a file or symbolic link.")
        }
        device = info.st_dev
        let decoded = try JSONDecoder().decode([CleanupRule].self, from: Data(contentsOf: rulesURL))
        rules = Dictionary(uniqueKeysWithValues: decoded.map {
            ($0.path.replacingOccurrences(of: "${HOME}", with: FileManager.default.homeDirectoryForCurrentUser.path), $0)
        })
    }

    static func displayed(_ path: String) -> String {
        path.hasPrefix(dataRoot + "/") ? String(path.dropFirst(dataRoot.count)) : path
    }

    private func classify(_ path: String, directory: Bool) -> CleanupRule? {
        if let rule = rules[path] { return rule }
        let name = (path as NSString).lastPathComponent
        if !directory && ["Docker.raw", "Docker.qcow2"].contains(name) {
            return CleanupRule(path: path, category: "review", label: "Docker disk image",
                guidance: "Contains containers, images and volumes, potentially databases. Inspect Docker Desktop; do not delete this file directly.")
        }
        if directory && name == "node_modules" && ["/src/", "/.codex/worktrees/", "/.codex/visualizations/"].contains(where: { path.hasPrefix(home + $0) }) {
            return CleanupRule(path: path, category: "rebuildable", label: "Project dependencies",
                guidance: "Confirm the manifest and lockfile exist and no manual edits are needed; reinstalling requires time and network access.")
        }
        if directory && name == ".venv" {
            return CleanupRule(path: path, category: "review", label: "Python virtual environment",
                guidance: "Check requirements or lockfile and confirm the environment is reproducible before removing it.")
        }
        return nil
    }

    private func issue(_ path: String, _ detail: String) {
        issueCount += 1
        if issues.count < 300 {
            issues.append(ScanIssue(path: Self.displayed(path), error: "AccessError", detail: detail))
        }
    }

    private func addCandidate(_ node: ScanNode, _ rule: CleanupRule) {
        guard node.bytes >= 10 * 1024 * 1024 else { return }
        candidates.append(Candidate(path: node.path, bytes: node.bytes, files: node.files,
            category: rule.category, label: rule.label, guidance: rule.guidance, incomplete: node.errors > 0))
    }

    private func updateProgress(_ path: String) {
        if Date().timeIntervalSince(lastProgress) >= 0.3 {
            lastProgress = Date()
            progress(files, directories, Self.displayed(path))
        }
    }

    private func walk(_ path: String) throws -> ScanNode {
        try cancellation.check()
        directories += 1
        updateProgress(path)
        let shown = Self.displayed(path)
        var node = ScanNode(name: (shown as NSString).lastPathComponent, path: shown, children: [])
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: path) }
        catch {
            issue(path, error.localizedDescription)
            node.errors = 1
            return node
        }
        for name in names {
            try cancellation.check()
            let entry = (path as NSString).appendingPathComponent(name)
            var info = stat()
            guard lstat(entry, &info) == 0 else {
                issue(entry, String(cString: strerror(errno)))
                node.errors += 1
                continue
            }
            let mode = info.st_mode & S_IFMT
            if mode == S_IFLNK { symlinks += 1; continue }
            if info.st_dev != device { mounts.append(Self.displayed(entry)); continue }
            var child: ScanNode
            if mode == S_IFDIR {
                child = try autoreleasepool { try walk(entry) }
            } else if mode == S_IFREG {
                if info.st_nlink > 1 {
                    let identity = "\(info.st_dev):\(info.st_ino)"
                    if !hardlinks.insert(identity).inserted { continue }
                }
                files += 1
                child = ScanNode(name: name, path: Self.displayed(entry), bytes: Int64(info.st_blocks) * 512,
                    logical_bytes: Int64(info.st_size), files: 1, kind: "file")
                if let rule = classify(child.path, directory: false) { addCandidate(child, rule) }
                if largest.count < 80 || child.bytes > (largest.last?.bytes ?? 0) {
                    largest.append(child)
                    largest.sort { $0.bytes > $1.bytes }
                    if largest.count > 80 { largest.removeLast() }
                }
                if files % 1000 == 0 { updateProgress(path) }
            } else { continue }
            node.bytes += child.bytes
            node.logical_bytes += child.logical_bytes
            node.files += child.files
            node.errors += child.errors
            if child.bytes >= minimum || child.errors > 0 || classify(child.path, directory: child.kind == "directory") != nil {
                node.children?.append(child)
            }
        }
        node.children?.sort { $0.bytes > $1.bytes }
        if let rule = classify(shown, directory: true) { addCandidate(node, rule) }
        return node
    }

    private func volume(freeAtStart: Int64? = nil) throws -> Volume {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/df")
        task.arguments = ["-kP", root]
        task.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let rows = String(decoding: output, as: UTF8.self).split(separator: "\n")
        let columns = rows.last?.split(whereSeparator: { $0.isWhitespace }) ?? []
        guard task.terminationStatus == 0, columns.count >= 4,
              let t = Int64(columns[1]), let u = Int64(columns[2]), let f = Int64(columns[3]) else {
            throw AssessmentError.message("Could not read storage capacity for this volume.")
        }
        return Volume(total: t*1024, used: u*1024, free: f*1024,
            other_shared_usage: max(0, (t-u-f)*1024), free_at_start: freeAtStart ?? f*1024, source: "/bin/df -kP")
    }

    func run() throws -> Snapshot {
        let start = Date()
        let before = try volume()
        let tree = try walk(root)
        try cancellation.check()
        var selected: [Candidate] = []
        for candidate in candidates.sorted(by: {
            let a = $0.path.split(separator: "/").count, b = $1.path.split(separator: "/").count
            return a == b ? $0.path < $1.path : a < b
        }) {
            if !selected.contains(where: { candidate.path.hasPrefix($0.path + "/") }) {
                selected.append(candidate)
            }
        }
        return Snapshot(version: 1, scanned_at: ISO8601DateFormatter().string(from: Date()),
            duration_seconds: (Date().timeIntervalSince(start)*10).rounded()/10, root: root, home: home,
            volume: try volume(freeAtStart: before.free), tree: tree,
            candidates: selected.sorted { $0.bytes > $1.bytes }, largest_files: largest,
            coverage: Coverage(files: files, directories: directories, symlinks_skipped: symlinks,
                mounts_skipped: mounts, error_count: issueCount, errors: issues, tree_minimum_bytes: minimum),
            method: ["Allocated bytes from lstat st_blocks × 512; file contents are never opened.",
                "Symlinks and other filesystem devices are skipped. Hard links count once, at the first encountered path.",
                "Directory metadata, snapshots, sibling volumes and inaccessible content are not included in the file sum.",
                "APFS clones can share blocks. Allocated byte sums are not guaranteed unique physical usage or reclaimable space.",
                "This is a live scan, not an atomic snapshot. Paths and sizes can change.",
                "Candidates are path-based review hints. No files are proven safe to remove. Candidate paths do not overlap."])
    }
}
