import Foundation

@main struct AssessmentModelTests {
    @MainActor static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("assessment-model-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("scan")
        let folder = root.appendingPathComponent("Folder")
        let sibling = root.appendingPathComponent("Sibling")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data(repeating: 42, count: 8192).write(to: folder.appendingPathComponent("one.bin"))
        try Data(repeating: 21, count: 4096).write(to: sibling.appendingPathComponent("two.bin"))
        let rules = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("resources/cleanup-rules.json")
        let initial = try DiskScanner(root: root.path, rulesURL: rules, cancellation: ScanCancellation(), minimum: 1).run()
        let cache = temporary.appendingPathComponent("cache/last-report.json")
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        var payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(initial)) as! [String: Any]
        payload["optional_extension"] = ["source": "synthetic"]
        let original = try JSONSerialization.data(withJSONObject: payload)
        try original.write(to: cache)
        let model = AssessmentModel(cacheURL: cache, rulesURL: rules)
        assert(model.snapshot?.tree.bytes == initial.tree.bytes && model.showingWelcome)
        assert(model.reportData == original) // Preserve optional/unknown report fields on export.
        model.report()
        model.visit(folder.path)
        assert(model.currentFolder?.path == folder.path)

        // Immediate cancellation must retain the saved report and navigation.
        model.startScan(root.path)
        assert(model.busy)
        model.visit(sibling.path)
        assert(model.currentFolder?.path == folder.path)
        model.cancel()
        try await finish(model)
        let afterCancellation = try Data(contentsOf: cache)
        assert(afterCancellation == original)
        assert(model.reportData == original)
        assert(model.currentFolder?.path == folder.path && !model.showingWelcome)

        let oldSibling = model.index?.nodes[sibling.path]?.bytes
        try Data(repeating: 63, count: 32768).write(to: folder.appendingPathComponent("new.bin"))
        model.refreshFolder()
        assert(model.refreshing && model.busy)
        try await finish(model)
        assert(!model.showingMessage, model.message ?? "Unexpected scan error")
        assert(model.currentFolder?.path == folder.path)
        assert(model.currentFolder!.bytes > initial.tree.children!.first(where: { $0.path == folder.path })!.bytes)
        assert(model.index?.nodes[sibling.path]?.bytes == oldSibling)
        assert(model.snapshot?.scanned_at == initial.scanned_at)
        assert(model.snapshot?.folder_refreshes?.first?.path == folder.path)
        let saved = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: cache))
        assert(saved.folder_refreshes?.count == 1)
        let permissions = try FileManager.default.attributesOfItem(atPath: cache.path)[.posixPermissions] as? Int
        assert(permissions == 0o600)

        // Failed scans and stale refresh targets retain the last successful report.
        let refreshedBytes = model.snapshot!.tree.bytes
        model.startScan(root.appendingPathComponent("missing").path)
        try await finish(model)
        assert(model.showingMessage && model.snapshot?.tree.bytes == refreshedBytes)
        model.showingMessage = false
        try FileManager.default.removeItem(at: folder)
        model.refreshFolder()
        assert(!model.busy && model.showingMessage && model.snapshot?.tree.bytes == refreshedBytes)
        print("Native lifecycle: isolated report loading, cancellation, navigation lock, partial refresh, private save and failure preservation passed.")
    }

    @MainActor static func finish(_ model: AssessmentModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        assert(!model.busy, "Fixture scan timed out")
    }
}
