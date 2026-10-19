import Foundation
import Darwin

@main
struct ScannerTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("disk-assessment-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("child")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("payload")
        try Data(repeating: 120, count: 16384).write(to: file)
        try fm.linkItem(at: file, to: root.appendingPathComponent("hardlink"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("cycle"), withDestinationURL: root)
        let rules = root.appendingPathComponent("rules.json")
        try Data("[]".utf8).write(to: rules)
        let token = ScanCancellation()
        let scanner = try DiskScanner(root: folder.path, rulesURL: rules, cancellation: token)
        let one = try scanner.run()
        var info = stat()
        precondition(lstat(file.path, &info) == 0)
        precondition(one.tree.bytes == Int64(info.st_blocks)*512, "Allocated blocks must match lstat")
        precondition(one.tree.logical_bytes == 16384 && one.tree.files == 1)

        let linked = try DiskScanner(root: root.path, rulesURL: rules, cancellation: ScanCancellation()).run()
        precondition(linked.tree.files == 2, "Hardlink must be counted once; rules file once")
        precondition(linked.coverage.symlinks_skipped == 1, "Do not follow directory cycles")
        let sparse = folder.appendingPathComponent("sparse")
        fm.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.seek(toOffset: 1024*1024)
        try handle.write(contentsOf: Data([1]))
        try handle.close()
        let sparseResult = try DiskScanner(root: folder.path, rulesURL: rules, cancellation: ScanCancellation()).run()
        var sparseInfo = stat()
        precondition(lstat(sparse.path, &sparseInfo) == 0)
        precondition(sparseResult.tree.bytes == Int64(info.st_blocks+sparseInfo.st_blocks)*512)
        precondition(sparseResult.tree.logical_bytes == 16384 + 1024*1024+1)
        let alias = root.appendingPathComponent("cycle")
        do {
            _ = try DiskScanner(root: alias.path, rulesURL: rules, cancellation: ScanCancellation())
            fatalError("Symlink root accepted")
        } catch is AssessmentError { }
        let cancelled = ScanCancellation()
        cancelled.cancel()
        do {
            _ = try DiskScanner(root: folder.path, rulesURL: rules, cancellation: cancelled).run()
            fatalError("Cancelled scan returned a snapshot")
        } catch is CancellationError { }
        let encoded = try JSONEncoder().encode(sparseResult)
        let decoded = try JSONDecoder().decode(Snapshot.self, from: encoded)
        precondition(decoded.tree.bytes == sparseResult.tree.bytes)
        let legacy = Data("{\"path\":\"/example/file\",\"bytes\":4096,\"logical_bytes\":5000}".utf8)
        let legacyNode = try JSONDecoder().decode(ScanNode.self, from: legacy)
        precondition(legacyNode.name == "file" && legacyNode.kind == "file")
        print("Native scanner: allocation, sparse files, hardlinks, symlinks, cancellation and snapshot compatibility passed.")
    }
}
