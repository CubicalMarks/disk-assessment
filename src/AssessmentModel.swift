import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class AssessmentModel: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var index: ReportIndex?
    @Published private(set) var navigation: ReportNavigation?
    @Published var section: ReportSection? = .overview
    @Published var showingWelcome = true
    @Published var selectedPath: String?
    @Published var reviewedPaths = Set<String>()
    @Published private(set) var scanRoot: String?
    @Published private(set) var refreshing = false
    @Published private(set) var progressFiles = 0
    @Published private(set) var progressDirectories = 0
    @Published private(set) var progressPath = ""
    @Published private(set) var cancelling = false
    @Published var message: String?
    @Published var showingMessage = false
    private var cancellation: ScanCancellation?
    private(set) var reportData: Data?
    private let cacheURL: URL
    private let rulesURL: URL
    var busy: Bool { cancellation != nil }
    var currentFolder: ScanNode? { navigation.flatMap { index?.nodes[$0.current] } }
    var selectedNode: ScanNode? {
        guard let path = selectedPath else { return nil }
        if let node = index?.nodes[path] { return node }
        if let node = snapshot?.largest_files.first(where: { $0.path == path }) { return node }
        if let candidate = snapshot?.candidates.first(where: { $0.path == path }) {
            return ScanNode(name: (path as NSString).lastPathComponent, path: path, bytes: candidate.bytes,
                files: candidate.files, kind: "candidate", errors: candidate.incomplete ? 1 : 0)
        }
        if let folder = currentFolder { return index?.children(of: folder).first { $0.path == path } }
        return nil
    }

    init(cacheURL: URL? = nil, rulesURL: URL? = nil) {
        self.rulesURL = rulesURL ?? Bundle.main.resourceURL!.appendingPathComponent("cleanup-rules.json")
        if let cacheURL {
            self.cacheURL = cacheURL
        } else if let override = ProcessInfo.processInfo.environment["DISK_ASSESSMENT_REPORT_PATH"] {
            self.cacheURL = URL(fileURLWithPath: override)
        } else {
            self.cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Disk Assessment", isDirectory: true).appendingPathComponent("last-report.json")
        }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--import-snapshot"), args.count > i + 1 {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: args[i + 1]))
                apply(try JSONDecoder().decode(Snapshot.self, from: data), preservingNavigation: false)
                reportData = data
                showingWelcome = false
            } catch { message = "The imported report could not be read. \(error.localizedDescription)"; showingMessage = true }
        } else if let data = try? Data(contentsOf: self.cacheURL) {
            do {
                apply(try JSONDecoder().decode(Snapshot.self, from: data), preservingNavigation: false)
                reportData = data
            }
            catch { message = "The saved report could not be read. Start a new scan."; showingMessage = true }
        }
    }

    private func apply(_ result: Snapshot, preservingNavigation: Bool) {
        let fresh = ReportIndex(result)
        if preservingNavigation, let old = index, var history = navigation {
            history.rebase(from: old, to: fresh, root: result.tree.path)
            navigation = history
        } else {
            navigation = ReportNavigation(root: result.tree.path)
            selectedPath = nil
            reviewedPaths = []
        }
        snapshot = result
        index = fresh
        reviewedPaths.formIntersection(Set(result.candidates.map(\.path)))
        if let selectedPath, !fresh.allowedPaths.contains(selectedPath) { self.selectedPath = nil }
    }

    func report() { if snapshot != nil { showingWelcome = false } }
    func newScan() { guard !busy else { return }; showingWelcome = true }
    func visit(_ path: String) {
        guard !busy, index?.nodes[path]?.kind == "directory" else { return }
        navigation?.visit(path)
        selectedPath = nil
        section = .explore
    }
    func back() { guard !busy else { return }; navigation?.back(); selectedPath = nil }
    func forward() { guard !busy else { return }; navigation?.forward(); selectedPath = nil }
    func up() {
        guard let path = currentFolder?.path, let parent = index?.parents[path] else { return }
        visit(parent)
    }
    func select(_ node: ScanNode) { guard !busy else { return }; selectedPath = node.path }
    func notify(_ text: String) { message = text; showingMessage = true }
    func scanMac() { startScan(DiskScanner.dataRoot) }
    func chooseFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to assess"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan Folder"
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url { self?.startScan(url.path) }
        }
    }
    func refreshFolder() {
        guard !busy, let snapshot, let folder = currentFolder else { return }
        do { try SnapshotRefresh.validate(folder.path, in: snapshot); startScan(folder.path, updating: snapshot) }
        catch { notify(error.localizedDescription) }
    }
    func cancel() {
        cancellation?.cancel()
        if busy { cancelling = true }
    }
    func shutdown() { cancellation?.cancel() }

    func startScan(_ root: String, updating previous: Snapshot? = nil) {
        guard !busy else { return }
        let token = ScanCancellation()
        cancellation = token
        scanRoot = root
        refreshing = previous != nil
        cancelling = false
        progressFiles = 0
        progressDirectories = 0
        progressPath = ""
        let rulesURL = self.rulesURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let scanner = try DiskScanner(root: root, rulesURL: rulesURL, cancellation: token,
                    minimum: previous?.coverage.tree_minimum_bytes ?? 50 * 1024 * 1024,
                    displayRoot: previous == nil ? nil : root) { files, directories, path in
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.cancellation === token else { return }
                            self.progressFiles = files
                            self.progressDirectories = directories
                            self.progressPath = path
                        }
                    }
                let scanned = try scanner.run()
                let result = try previous.map { try SnapshotRefresh.merging(scanned, into: $0, at: DiskScanner.displayed(root)) } ?? scanned
                let data = try JSONEncoder().encode(result)
                try token.check()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.cancellation === token else { return }
                    do { try token.check() }
                    catch { self.finishScan(); return }
                    self.apply(result, preservingNavigation: previous != nil)
                    self.reportData = data
                    self.showingWelcome = false
                    if previous == nil { self.section = .overview }
                    self.finishScan()
                    do { try self.saveCache(data) }
                    catch { self.notify("The report is available, but could not be saved for the next launch.") }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.cancellation === token else { return }
                    self.finishScan()
                    if !(error is CancellationError) { self.notify(error.localizedDescription) }
                }
            }
        }
    }
    private func finishScan() {
        cancellation = nil
        scanRoot = nil
        refreshing = false
        cancelling = false
    }
    private func saveCache(_ data: Data) throws {
        let directory = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: cacheURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
    }
    func finder(_ path: String, openFolder: Bool = false) {
        do {
            let target = try FinderTarget.resolve(path, allowed: index?.allowedPaths ?? [])
            if openFolder && target.isDirectory {
                if !NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: target.path) { notify("Finder could not open this folder.") }
            } else { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target.path)]) }
        } catch { notify(error.localizedDescription) }
    }
    func copy(_ paths: [String]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }
    func export() {
        guard let reportData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Disk Assessment.json"
        panel.title = "Export assessment snapshot"
        panel.message = "This report includes local file paths. Choose where to save it."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try reportData.write(to: url, options: .atomic) }
            catch { self?.notify(error.localizedDescription) }
        }
    }
}
