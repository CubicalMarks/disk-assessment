import AppKit
import WebKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var snapshot: Data?
    private var cancellation: ScanCancellation?
    private var currentFolder: String?
    private var currentItem: String?
    private var allowedPaths = Set<String>()
    private let resources = Bundle.main.resourceURL!
    private let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Disk Assessment", isDirectory: true).appendingPathComponent("last-report.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        makeMenu()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "diskAssessment")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Disk Assessment"
        window.minSize = NSSize(width: 760, height: 600)
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName("AssessmentWindow")
        snapshot = try? Data(contentsOf: cacheURL)
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--import-snapshot"), args.count > index + 1,
           let imported = try? Data(contentsOf: URL(fileURLWithPath: args[index+1])),
           (try? JSONDecoder().decode(Snapshot.self, from: imported)) != nil {
            snapshot = imported
            try? saveCache(imported)
        }
        webView.loadFileURL(resources.appendingPathComponent("index.html"), allowingReadAccessTo: resources)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "About Disk Assessment", action: #selector(about), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Disk Assessment", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Disk Assessment",
            .applicationVersion: "0.3", .credits: NSAttributedString(string: "Local, read-only storage assessment. No file contents read and no deletion controls.")])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { cancellation?.cancel() }

    private func event(_ name: String, _ value: Any = NSNull()) {
        webView.callAsyncJavaScript("window.nativeEvent(name, value)", arguments: ["name": name, "value": value], in: nil, in: .page, completionHandler: { _ in })
    }

    private func showSnapshot() {
        guard let snapshot, let text = String(data: snapshot, encoding: .utf8),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: snapshot) else {
            event("error", "The saved report could not be read. Start a new scan.")
            return
        }
        allowedPaths.removeAll()
        func collect(_ node: ScanNode) {
            allowedPaths.insert(node.path)
            for child in node.children ?? [] { collect(child) }
        }
        collect(decoded.tree)
        decoded.candidates.forEach { allowedPaths.insert($0.path) }
        decoded.largest_files.forEach { allowedPaths.insert($0.path) }
        currentFolder = decoded.tree.path
        currentItem = nil
        webView.callAsyncJavaScript("window.receiveSnapshot(JSON.parse(json))", arguments: ["json": text], in: nil, in: .page, completionHandler: { _ in })
    }

    private func saveCache(_ data: Data) throws {
        let directory = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try data.write(to: cacheURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
    }

    private func startScan(_ root: String, updating previous: Snapshot? = nil) {
        guard cancellation == nil else { return }
        let token = ScanCancellation()
        cancellation = token
        event("scanning", root)
        let rulesURL = resources.appendingPathComponent("cleanup-rules.json")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let scanner = try DiskScanner(root: root, rulesURL: rulesURL, cancellation: token, minimum: previous?.coverage.tree_minimum_bytes ?? 50 * 1024 * 1024, displayRoot: previous == nil ? nil : root) { files, dirs, path in
                    DispatchQueue.main.async { [weak self] in
                        guard self?.cancellation === token else { return }
                        self?.event("progress", ["files": files, "directories": dirs, "path": path])
                    }
                }
                let scanned = try scanner.run()
                let result = try previous.map { try SnapshotRefresh.merging(scanned, into: $0, at: DiskScanner.displayed(root)) } ?? scanned
                let data = try JSONEncoder().encode(result)
                try token.check()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.cancellation === token else { return }
                    do { try token.check() }
                    catch {
                        self.cancellation = nil
                        self.event("cancelled", self.snapshot != nil)
                        return
                    }
                    self.cancellation = nil
                    self.snapshot = data
                    do { try self.saveCache(data) }
                    catch { self.event("saveWarning", "The report is available, but could not be saved for the next launch.") }
                    self.showSnapshot()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.cancellation === token else { return }
                    self.cancellation = nil
                    if error is CancellationError { self.event("cancelled", self.snapshot != nil) }
                    else { self.event("error", error.localizedDescription) }
                }
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, webView.url?.isFileURL == true,
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready": event("ready", snapshot != nil)
        case "viewLast": showSnapshot()
        case "scanMac": startScan(DiskScanner.dataRoot)
        case "rescan":
            guard cancellation == nil, let path = body["path"] as? String,
                  path == currentFolder, allowedPaths.contains(path), let snapshot else {
                event("rescanError", "This folder is no longer part of the current report.")
                return
            }
            do {
                let previous = try JSONDecoder().decode(Snapshot.self, from: snapshot)
                try SnapshotRefresh.validate(path, in: previous)
                startScan(path, updating: previous)
            } catch { event("rescanError", error.localizedDescription) }
        case "chooseFolder":
            guard cancellation == nil else { return }
            let panel = NSOpenPanel()
            panel.title = "Choose a folder to assess"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Scan Folder"
            panel.beginSheetModal(for: window) { [weak self] response in
                if response == .OK, let url = panel.url { self?.startScan(url.path) }
            }
        case "cancel":
            cancellation?.cancel()
        case "copy":
            guard let text = body["text"] as? String, text.utf8.count < 1_000_000 else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            event("copied")
        case "folder":
            if let path = body["path"] as? String, allowedPaths.contains(path) { currentFolder = path }
        case "selection":
            if let path = body["path"] as? String, allowedPaths.contains(path) { currentItem = path }
        case "finder", "reveal":
            if let path = body["path"] as? String ?? currentItem ?? currentFolder {
                showInFinder(path, openFolder: (body["openFolder"] as? Bool) ?? false)
            }
        case "contextMenu":
            if let path = body["path"] as? String, allowedPaths.contains(path) {
                let x = body["x"] as? Double ?? 30
                let y = body["y"] as? Double ?? 30
                DispatchQueue.main.async { [weak self] in self?.showItemMenu(path, x: x, y: y) }
            }
        case "export":
            guard let snapshot else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "Disk Assessment.json"
            panel.title = "Export assessment snapshot"
            panel.message = "This report includes local file paths. Choose where to save it."
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                do { try snapshot.write(to: url, options: .atomic) }
                catch { self?.event("saveWarning", error.localizedDescription) }
            }
        default: break
        }
    }

    private func showInFinder(_ path: String, openFolder: Bool) {
        do {
            let target = try FinderTarget.resolve(path, allowed: allowedPaths)
            let url = URL(fileURLWithPath: target.path)
            if openFolder && target.isDirectory {
                if !NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: target.path) { event("actionError", "Finder could not open this folder.") }
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } catch { event("actionError", error.localizedDescription) }
    }

    private func showItemMenu(_ path: String, x: Double, y: Double) {
        do {
            let target = try FinderTarget.resolve(path, allowed: allowedPaths)
            let menu = NSMenu()
            if target.isDirectory {
                let item = NSMenuItem(title: "Open in Finder", action: #selector(itemMenuAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ["path": path, "action": "open"]
                menu.addItem(item)
            }
            let reveal = NSMenuItem(title: "Show in Finder", action: #selector(itemMenuAction(_:)), keyEquivalent: "")
            reveal.target = self
            reveal.representedObject = ["path": path, "action": "reveal"]
            menu.addItem(reveal)
            menu.addItem(.separator())
            let copy = NSMenuItem(title: "Copy Path", action: #selector(itemMenuAction(_:)), keyEquivalent: "")
            copy.target = self
            copy.representedObject = ["path": path, "action": "copy"]
            menu.addItem(copy)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            let point = NSPoint(x: min(max(0, x), webView.bounds.width),
                y: webView.isFlipped ? y : webView.bounds.height - y)
            menu.popUp(positioning: nil, at: point, in: webView)
        } catch { event("actionError", error.localizedDescription) }
    }

    @objc private func itemMenuAction(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String],
              let path = info["path"], allowedPaths.contains(path) else { return }
        if info["action"] == "copy" {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            event("copied")
        } else { showInFinder(path, openFolder: info["action"] == "open") }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL && url.standardizedFileURL.path.hasPrefix(resources.path + "/") {
            decisionHandler(.allow)
        } else {
            if navigationAction.navigationType == .linkActivated && ["https", "http"].contains(url.scheme ?? "") {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }
}

@main
struct DiskAssessmentApp {
    static func main() {
if let i = CommandLine.arguments.firstIndex(of: "--scan"), CommandLine.arguments.count > i+1 {
    do {
        let args = CommandLine.arguments
        let rules = Bundle.main.resourceURL?.appendingPathComponent("cleanup-rules.json")
            ?? URL(fileURLWithPath: "resources/cleanup-rules.json")
        let scanner = try DiskScanner(root: args[i+1], rulesURL: rules, cancellation: ScanCancellation())
        let result = try JSONEncoder().encode(scanner.run())
        if let output = args.firstIndex(of: "--output"), args.count > output+1 {
            try result.write(to: URL(fileURLWithPath: args[output+1]), options: .atomic)
        } else { FileHandle.standardOutput.write(result) }
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

    }
}
