import Foundation

@main
struct FinderActionsTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("finder-action-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("file.txt")
        try Data("fixture".utf8).write(to: file)
        let allowed: Set<String> = [root.path, file.path, root.appendingPathComponent("missing").path]
        let folderTarget = try FinderTarget.resolve(root.path, allowed: allowed)
        let fileTarget = try FinderTarget.resolve(file.path, allowed: allowed)
        precondition(folderTarget.isDirectory)
        precondition(!fileTarget.isDirectory)
        do {
            _ = try FinderTarget.resolve("/etc/passwd", allowed: allowed)
            fatalError("An unscanned path was accepted")
        } catch is AssessmentError { }
        do {
            _ = try FinderTarget.resolve(root.appendingPathComponent("missing").path, allowed: allowed)
            fatalError("A missing item was accepted")
        } catch is AssessmentError { }
        print("Finder actions: report allowlist, file/folder targets and stale paths passed without opening any items.")
    }
}
