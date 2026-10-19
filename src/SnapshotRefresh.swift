import Foundation
import Darwin

struct FolderRefresh: Codable {
    let path: String
    let scanned_at: String
    let duration_seconds: Double
}

// A folder refresh replaces one measured subtree; all other measurements keep
// their original age. It must not make the whole report appear newly scanned.
enum SnapshotRefresh {
    static func contains(_ path: String, in folder: String) -> Bool {
        path == folder || path.hasPrefix(folder == "/" ? "/" : folder + "/")
    }

    static func node(_ path: String, in tree: ScanNode) -> ScanNode? {
        if tree.path == path { return tree }
        for child in tree.children ?? [] {
            if let found = node(path, in: child) { return found }
        }
        return nil
    }

    static func validate(_ path: String, in snapshot: Snapshot) throws {
        guard node(path, in: snapshot.tree)?.kind == "directory" else {
            throw AssessmentError.message("This folder is not part of the current report.")
        }
        var root = stat(), folder = stat()
        guard lstat(snapshot.root, &root) == 0, lstat(path, &folder) == 0,
              folder.st_mode & S_IFMT == S_IFDIR else {
            throw AssessmentError.message("This folder has moved or is no longer a regular folder. Start a new scan.")
        }
        guard root.st_dev == folder.st_dev else {
            throw AssessmentError.message("This folder is now on a different filesystem. Scan it as a new folder instead.")
        }
    }

    static func merging(_ fresh: Snapshot, into original: Snapshot, at path: String) throws -> Snapshot {
        guard let old = node(path, in: original.tree), old.kind == "directory",
              fresh.tree.path == path, fresh.coverage.tree_minimum_bytes == original.coverage.tree_minimum_bytes else {
            throw AssessmentError.message("The refreshed folder does not match the current report.")
        }
        if path == original.tree.path { return fresh }

        func replace(_ node: ScanNode) -> (ScanNode, Bool) {
            if node.path == path { return (fresh.tree, true) }
            var updated = node
            for (index, child) in (node.children ?? []).enumerated() {
                let (replacement, found) = replace(child)
                if found {
                    updated.children?[index] = replacement
                    updated.children?.sort { $0.bytes > $1.bytes }
                    updated.bytes += fresh.tree.bytes - old.bytes
                    updated.logical_bytes += fresh.tree.logical_bytes - old.logical_bytes
                    updated.files += fresh.tree.files - old.files
                    updated.errors += fresh.tree.errors - old.errors
                    return (updated, true)
                }
            }
            return (node, false)
        }
        let tree = replace(original.tree).0
        var candidates = original.candidates.compactMap { candidate -> Candidate? in
            if contains(candidate.path, in: path) { return nil }
            if contains(path, in: candidate.path), let updated = node(candidate.path, in: tree) {
                guard updated.bytes >= 10 * 1024 * 1024 else { return nil }
                return Candidate(path: candidate.path, bytes: updated.bytes, files: updated.files,
                    category: candidate.category, label: candidate.label, guidance: candidate.guidance,
                    incomplete: updated.errors > 0)
            }
            return candidate
        }
        candidates += fresh.candidates
        var selected: [Candidate] = []
        for candidate in candidates.sorted(by: { $0.path.count < $1.path.count }) {
            if !selected.contains(where: { contains(candidate.path, in: $0.path) }) { selected.append(candidate) }
        }
        let largest = (original.largest_files.filter { !contains($0.path, in: path) } + fresh.largest_files)
            .sorted { $0.bytes > $1.bytes }
        let errors = original.coverage.errors.filter { !contains($0.path, in: path) } + fresh.coverage.errors
        // Legacy snapshots do not store per-folder directory/symlink counts.
        // Retain those baseline coverage counters and label their age in the UI.
        let coverage = Coverage(files: tree.files, directories: original.coverage.directories,
            symlinks_skipped: original.coverage.symlinks_skipped, mounts_skipped: original.coverage.mounts_skipped,
            error_count: tree.errors, errors: Array(errors.prefix(300)),
            tree_minimum_bytes: original.coverage.tree_minimum_bytes)
        var refreshes = (original.folder_refreshes ?? []).filter { !contains($0.path, in: path) }
        refreshes.append(FolderRefresh(path: path, scanned_at: fresh.scanned_at, duration_seconds: fresh.duration_seconds))
        let note = "Folder rescans update only the selected subtree. Other folders and directory/symlink/mount coverage counters retain their original scan measurements. Largest files are the largest known entries; a full scan is needed to rebuild the global ranking."
        var method = original.method.map { text in
            text.localizedCaseInsensitiveContains("hard link")
                ? "Symlinks and other filesystem devices are skipped. Hard links count once within each scan; links shared between refreshed and older folders may be counted differently. Run a full scan to reconcile them."
                : text
        }
        if !method.contains(note) { method.append(note) }
        return Snapshot(version: original.version, scanned_at: original.scanned_at,
            duration_seconds: original.duration_seconds, root: original.root, home: original.home,
            volume: fresh.volume, tree: tree, candidates: selected.sorted { $0.bytes > $1.bytes },
            largest_files: Array(largest.prefix(80)), coverage: coverage, method: method,
            folder_refreshes: refreshes)
    }
}
