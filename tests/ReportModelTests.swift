import Foundation
import CoreGraphics

@main struct ReportModelTests {
    static func main() throws {
        let leaf = ScanNode(name: "Tiny", path: "/fixture/Folder/Tiny", bytes: 1, kind: "file")
        let folder = ScanNode(name: "Folder", path: "/fixture/Folder", bytes: 100, children: [leaf])
        let sibling = ScanNode(name: "Sibling", path: "/fixture/Sibling", bytes: 900, kind: "file")
        let root = ScanNode(name: "fixture", path: "/fixture", bytes: 1100, children: [folder, sibling])
        func snapshot(_ tree: ScanNode) -> Snapshot {
            Snapshot(version: 1, scanned_at: "2026-10-20T12:00:00Z", duration_seconds: 1, root: root.path, home: "/fixture",
                volume: Volume(total: 2000, used: 1500, free: 500, other_shared_usage: 0, free_at_start: 500, source: "fixture"),
                tree: tree, candidates: [Candidate(path: "/fixture/Candidate", bytes: 10, files: 1, category: "review", label: "Test", guidance: "Review", incomplete: false)],
                largest_files: [ScanNode(name: "Hidden", path: "/fixture/Hidden", bytes: 50, kind: "file")],
                coverage: Coverage(files: 3, directories: 2, symlinks_skipped: 0, mounts_skipped: [], error_count: 0, errors: [], tree_minimum_bytes: 1), method: [])
        }
        let original = snapshot(root)
        let index = ReportIndex(original)
        assert(index.chain(leaf.path).map(\.path) == [root.path, folder.path, leaf.path])
        assert(index.allowedPaths.contains("/fixture/Hidden") && index.allowedPaths.contains("/fixture/Candidate"))
        assert(!index.allowedPaths.contains("/fixture/not-in-report"))
        let children = index.children(of: root)
        assert(children.reduce(0) { $0 + $1.bytes } == root.bytes)
        assert(children.first(where: { $0.kind == "other" })?.bytes == 100)
        assert(children.allSatisfy { $0.kind != "other" || !index.allowedPaths.contains($0.path) })

        var navigation = ReportNavigation(root: root.path)
        navigation.visit(folder.path)
        navigation.visit(leaf.path)
        navigation.back()
        assert(navigation.current == folder.path && navigation.canForward)
        let changedFolder = ScanNode(name: "Folder", path: folder.path, bytes: 300, children: [])
        let changedRoot = ScanNode(name: root.name, path: root.path, bytes: 1200, children: [changedFolder, sibling])
        let fresh = ReportIndex(snapshot(changedRoot))
        navigation.rebase(from: index, to: fresh, root: root.path)
        navigation.forward()
        assert(navigation.current == folder.path) // A removed entry falls back to its nearest surviving parent.
        assert(fresh.nodes[navigation.current]?.bytes == 300)
        navigation.back()
        navigation.visit(root.path)
        assert(!navigation.canForward)
        let replaced = ReportIndex(snapshot(ScanNode(name: root.name, path: root.path, bytes: 0, children: [])))
        navigation.rebase(from: fresh, to: replaced, root: root.path)
        assert(navigation.entries.allSatisfy { $0 == root.path })

        let nodes = [sibling, folder, leaf]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(nodes)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        for balanced in [false, true] {
            let tiles = StorageMap.layout(nodes, in: bounds, balanced: balanced)
            assert(tiles.count == nodes.count)
            let totalArea = tiles.reduce(0.0) { $0 + $1.rect.width * $1.rect.height }
            assert(abs(totalArea - bounds.width * bounds.height) < 0.001)
            for (i, tile) in tiles.enumerated() {
                assert(bounds.contains(tile.rect))
                assert(tile.rect.width > 0 && tile.rect.height > 0)
                for other in tiles.dropFirst(i + 1) {
                    let overlap = tile.rect.intersection(other.rect)
                    assert(overlap.isNull || overlap.width * overlap.height < 0.001)
                }
                if !balanced {
                    let actual = tile.rect.width * tile.rect.height / totalArea
                    assert(abs(actual - Double(tile.node.bytes) / 1001) < 0.00001)
                }
            }
        }
        let afterLayout = try encoder.encode(nodes)
        assert(afterLayout == encoded)
        let balanced = StorageMap.layout(nodes, in: bounds, balanced: true)
        assert(balanced.last!.rect.width * balanced.last!.rect.height / 400000 > 0.1)
        assert(StorageMap.layout([], in: bounds, balanced: true).isEmpty)
        assert(StorageMap.layout(nodes, in: .zero, balanced: true).isEmpty)
        assert(StorageMap.layout([ScanNode(name: "empty", path: "/empty", bytes: 0)], in: bounds, balanced: false).isEmpty)
        assert(StorageMap.paletteIndex("/fixture/Folder") == StorageMap.paletteIndex("/fixture/Folder"))
        print("Native report: navigation rebasing, allowlists, threshold remainders and truthful map areas/bounds passed.")
    }
}
