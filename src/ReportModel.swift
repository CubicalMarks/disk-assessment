import Foundation
import CoreGraphics

// Shared native presentation calculations; measured bytes never change with map scale.
enum ReportSection: String, CaseIterable, Identifiable {
    case overview = "Overview", explore = "Storage Map", review = "Review", largest = "Large Files", coverage = "Scan Details"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "chart.pie"
        case .explore: return "square.grid.2x2"
        case .review: return "checklist"
        case .largest: return "doc.text.magnifyingglass"
        case .coverage: return "info.circle"
        }
    }
}

struct ReportIndex {
    var nodes: [String: ScanNode] = [:]
    var parents: [String: String] = [:]
    var allowedPaths: Set<String> = []

    init(_ snapshot: Snapshot) {
        func visit(_ node: ScanNode, parent: String?) {
            nodes[node.path] = node
            allowedPaths.insert(node.path)
            if let parent { parents[node.path] = parent }
            for child in node.children ?? [] { visit(child, parent: node.path) }
        }
        visit(snapshot.tree, parent: nil)
        for node in snapshot.largest_files { allowedPaths.insert(node.path) }
        for candidate in snapshot.candidates { allowedPaths.insert(candidate.path) }
    }

    func chain(_ path: String) -> [ScanNode] {
        var result: [ScanNode] = []
        var current: String? = path
        while let path = current, let node = nodes[path] {
            result.insert(node, at: 0)
            current = parents[path]
        }
        return result
    }

    func children(of folder: ScanNode) -> [ScanNode] {
        let children = folder.children ?? []
        let remainder = folder.bytes - children.reduce(Int64(0)) { $0 + $1.bytes }
        let other = ScanNode(name: "Other entries", path: folder.path + "/\0other", bytes: remainder,
            logical_bytes: remainder, kind: "other")
        return (children + (remainder > 0 ? [other] : [])).sorted {
            $0.bytes == $1.bytes ? $0.path < $1.path : $0.bytes > $1.bytes
        }
    }
}

struct ReportNavigation {
    private(set) var entries: [String]
    private(set) var position = 0
    init(root: String) { entries = [root] }
    var current: String { entries[position] }
    var canBack: Bool { position > 0 }
    var canForward: Bool { position + 1 < entries.count }
    mutating func visit(_ path: String) {
        guard path != current else { return }
        entries = Array(entries.prefix(position + 1)) + [path]
        position += 1
    }
    mutating func back() { if canBack { position -= 1 } }
    mutating func forward() { if canForward { position += 1 } }
    mutating func rebase(from old: ReportIndex, to fresh: ReportIndex, root: String) {
        entries = entries.map { path in
            old.chain(path).reversed().first { fresh.nodes[$0.path]?.kind == "directory" }?.path ?? root
        }
    }
}

struct MapTile: Identifiable {
    let node: ScanNode
    let rect: CGRect
    var id: String { node.path }
}

enum StorageMap {
    static func paletteIndex(_ path: String) -> Int {
        var hash: UInt32 = 0
        for scalar in path.unicodeScalars { hash = hash &* 31 &+ scalar.value }
        return Int(hash % 8)
    }

    static func layout(_ nodes: [ScanNode], in bounds: CGRect, balanced: Bool) -> [MapTile] {
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        let positive = nodes.filter { $0.bytes > 0 }
        let sum = positive.reduce(0.0) { $0 + sqrt(Double($1.bytes)) }
        let floor = positive.isEmpty ? 0 : sum / (3 * Double(positive.count))
        let weighted = positive.map { ($0, balanced ? max(floor, sqrt(Double($0.bytes))) : Double($0.bytes)) }
        var output: [MapTile] = []
        func place(_ items: ArraySlice<(ScanNode, Double)>, _ rect: CGRect) {
            guard let first = items.first else { return }
            if items.count == 1 { output.append(MapTile(node: first.0, rect: rect)); return }
            let total = items.reduce(0.0) { $0 + $1.1 }
            var sum = 0.0
            var count = 0
            for item in items.dropLast() {
                let next = sum + item.1
                if count > 0 && abs(sum - total / 2) < abs(next - total / 2) { break }
                sum = next
                count += 1
            }
            count = max(1, count)
            let split = items.index(items.startIndex, offsetBy: count)
            let ratio = sum / total
            if rect.width >= rect.height {
                let width = rect.width * ratio
                place(items[..<split], CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height))
                place(items[split...], CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height))
            } else {
                let height = rect.height * ratio
                place(items[..<split], CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height))
                place(items[split...], CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height))
            }
        }
        place(weighted[...], bounds)
        return output
    }
}

enum ReportFormat {
    static func bytes(_ bytes: Int64) -> String {
        bytes == 0 ? "0 B" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }
    static func date(_ text: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) else { return text }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    static func percent(_ bytes: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0%" }
        return (Double(bytes) / Double(total)).formatted(.percent.precision(.fractionLength(1)))
    }
}
