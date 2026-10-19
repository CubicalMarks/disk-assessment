import Foundation

@main
struct SnapshotRefreshTests {
    static func main() throws {
        let mib: Int64 = 1024 * 1024
        func file(_ path: String, _ size: Int64) -> ScanNode {
            ScanNode(name: (path as NSString).lastPathComponent, path: path,
                bytes: size, logical_bytes: size, files: 1, kind: "file")
        }
        func folder(_ path: String, _ children: [ScanNode], errors: Int = 0) -> ScanNode {
            ScanNode(name: (path as NSString).lastPathComponent, path: path,
                bytes: children.reduce(0) { $0 + $1.bytes }, logical_bytes: children.reduce(0) { $0 + $1.logical_bytes },
                files: children.reduce(0) { $0 + $1.files }, errors: errors, children: children)
        }
        func candidate(_ node: ScanNode) -> Candidate {
            Candidate(path: node.path, bytes: node.bytes, files: node.files, category: "review",
                label: node.name, guidance: "Keep until reviewed.", incomplete: node.errors > 0)
        }
        func snapshot(_ tree: ScanNode, candidates: [Candidate], largest: [ScanNode], date: String) -> Snapshot {
            Snapshot(version: 1, scanned_at: date, duration_seconds: 2, root: tree.path, home: tree.path,
                volume: Volume(total: 1000*mib, used: 500*mib, free: 400*mib,
                    other_shared_usage: 100*mib, free_at_start: 400*mib, source: "fixture"),
                tree: tree, candidates: candidates, largest_files: largest,
                coverage: Coverage(files: tree.files, directories: 7, symlinks_skipped: 2,
                    mounts_skipped: [], error_count: tree.errors,
                    errors: tree.errors > 0 ? [ScanIssue(path: tree.path + "/a/missing", error: "AccessError", detail: "fixture")] : [],
                    tree_minimum_bytes: 0), method: ["Hard links count once, at the first encountered path."])
        }
        let oldFile = file("/root/a/old", 20*mib)
        let neighborFile = file("/root/a-other/keep", 30*mib)
        let a = folder("/root/a", [oldFile], errors: 1)
        let neighbor = folder("/root/a-other", [neighborFile])
        let parent = folder("/root", [a, neighbor], errors: 1)
        let original = snapshot(parent, candidates: [candidate(a), candidate(neighbor)],
            largest: [neighborFile, oldFile], date: "2026-01-01T00:00:00Z")
        let newFile = file("/root/a/new", 45*mib)
        let fresh = snapshot(folder(a.path, [newFile]), candidates: [candidate(newFile)], largest: [newFile], date: "2026-01-02T00:00:00Z")
        let updated = try SnapshotRefresh.merging(fresh, into: original, at: a.path)
        precondition(updated.root == original.root && updated.scanned_at == original.scanned_at)
        precondition(updated.tree.bytes == 75*mib && updated.tree.files == 2 && updated.tree.errors == 0)
        precondition(updated.tree.children?.first?.path == a.path, "Children must be re-sorted by updated size")
        precondition(SnapshotRefresh.node(neighbor.path, in: updated.tree)?.bytes == neighbor.bytes)
        precondition(SnapshotRefresh.node(oldFile.path, in: updated.tree) == nil)
        precondition(updated.largest_files.map(\.path) == [newFile.path, neighborFile.path])
        precondition(Set(updated.candidates.map(\.path)) == Set([newFile.path, neighbor.path]))
        precondition(updated.coverage.files == 2 && updated.coverage.error_count == 0 && updated.coverage.errors.isEmpty)
        precondition(updated.coverage.directories == original.coverage.directories)
        precondition(updated.folder_refreshes?.first?.path == a.path)
        precondition(updated.method.contains { $0.contains("shared between refreshed and older folders") })
        precondition(original.tree.bytes == 50*mib && original.coverage.error_count == 1, "Merge must not mutate the previous report")

        var withParent = original
        withParent = Snapshot(version: withParent.version, scanned_at: withParent.scanned_at, duration_seconds: 2,
            root: withParent.root, home: withParent.home, volume: withParent.volume, tree: withParent.tree,
            candidates: [candidate(parent)], largest_files: withParent.largest_files, coverage: withParent.coverage, method: withParent.method)
        let parentUpdated = try SnapshotRefresh.merging(fresh, into: withParent, at: a.path)
        precondition(parentUpdated.candidates.count == 1 && parentUpdated.candidates[0].bytes == 75*mib,
            "An enclosing candidate owns nested candidates and uses the updated total")
        let repeated = try SnapshotRefresh.merging(fresh, into: updated, at: a.path)
        precondition(repeated.folder_refreshes?.count == 1 && repeated.tree.bytes == updated.tree.bytes)
        let decoded = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(updated))
        precondition(decoded.folder_refreshes?.first?.scanned_at == fresh.scanned_at)
        let full = try SnapshotRefresh.merging(original, into: updated, at: parent.path)
        precondition(full.folder_refreshes == nil && full.scanned_at == original.scanned_at)
        for invalid in ["/root/missing", "/root/a-other", oldFile.path] {
            do {
                _ = try SnapshotRefresh.merging(fresh, into: original, at: invalid)
                fatalError("An invalid refresh was accepted")
            } catch is AssessmentError { }
        }
        precondition(!SnapshotRefresh.contains("/root/a-other", in: a.path))

        // Exercise the real scanner on fixtures: removed and newly allocated files,
        // while an outside folder deliberately changes but must retain its old data.
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("folder-refresh-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let inside = root.appendingPathComponent("inside")
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: inside, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let removed = inside.appendingPathComponent("removed")
        try Data(repeating: 1, count: 16384).write(to: removed)
        let untouched = outside.appendingPathComponent("untouched")
        try Data(repeating: 2, count: 16384).write(to: untouched)
        let rules = root.appendingPathComponent("rules.json")
        try Data("[]".utf8).write(to: rules)
        let before = try DiskScanner(root: root.path, rulesURL: rules, cancellation: ScanCancellation(), minimum: 0).run()
        try SnapshotRefresh.validate(inside.path, in: before)
        try fm.removeItem(at: removed)
        try Data(repeating: 3, count: 65536).write(to: inside.appendingPathComponent("added"))
        try Data(repeating: 4, count: 131072).write(to: untouched)
        let rescanned = try DiskScanner(root: inside.path, rulesURL: rules, cancellation: ScanCancellation(), minimum: 0, displayRoot: inside.path).run()
        let merged = try SnapshotRefresh.merging(rescanned, into: before, at: inside.path)
        precondition(SnapshotRefresh.node(inside.path, in: merged.tree)?.bytes == rescanned.tree.bytes)
        precondition(SnapshotRefresh.node(outside.path, in: merged.tree)?.bytes == SnapshotRefresh.node(outside.path, in: before.tree)?.bytes)
        precondition(!merged.largest_files.contains { $0.path == removed.path })
        let unlisted = root.appendingPathComponent("unlisted")
        try fm.createDirectory(at: unlisted, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: inside)
        for invalid in [unlisted.path, untouched.path] {
            do { try SnapshotRefresh.validate(invalid, in: before); fatalError("Invalid target accepted") }
            catch is AssessmentError { }
        }
        let aliasPath = "/private/tmp/disk-refresh-alias-\(UUID().uuidString)"
        let aliasRoot = URL(fileURLWithPath: aliasPath)
        try fm.createDirectory(atPath: aliasPath, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: aliasPath) }
        try Data([1]).write(to: aliasRoot.appendingPathComponent("file"))
        let aliasScan = try DiskScanner(root: aliasPath, rulesURL: rules, cancellation: ScanCancellation(), minimum: 0, displayRoot: aliasPath).run()
        precondition(aliasScan.tree.path == aliasPath && aliasScan.largest_files.first?.path == aliasPath + "/file",
            "Refresh must preserve /private/tmp aliases used by older or Python reports")
        try fm.removeItem(at: inside)
        try fm.createSymbolicLink(at: inside, withDestinationURL: outside)
        do { try SnapshotRefresh.validate(inside.path, in: before); fatalError("A replaced symlink was accepted") }
        catch is AssessmentError { }
        print("Folder refresh: subtree replacement, parent totals, siblings, candidates, stale files/errors, snapshot compatibility and scan-target validation passed.")
    }
}
