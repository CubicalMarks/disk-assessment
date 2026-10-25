import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AssessmentModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}

struct NativeAssessmentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AssessmentModel()

    var body: some Scene {
        Window("Disk Assessment", id: "main") {
            AssessmentView(model: model)
                .frame(minWidth: 1000, minHeight: 660)
                .preferredColorScheme(previewAppearance)
                .onAppear { delegate.model = model; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Scan", action: model.newScan).keyboardShortcut("n").disabled(model.busy)
                Button("Choose Folder…", action: model.chooseFolder).keyboardShortcut("o").disabled(model.busy)
                Button("Scan Mac", action: model.scanMac).disabled(model.busy)
                Divider()
                Button("View Last Report", action: model.report).disabled(model.snapshot == nil || model.busy)
                Button("Export Snapshot…", action: model.export).keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.snapshot == nil || model.busy)
            }
            CommandMenu("Navigate") {
                Button("Back", action: model.back).keyboardShortcut("[").disabled(model.busy || model.navigation?.canBack != true)
                Button("Forward", action: model.forward).keyboardShortcut("]").disabled(model.busy || model.navigation?.canForward != true)
                Button("Enclosing Folder", action: model.up).keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(model.busy || model.currentFolder.flatMap { model.index?.parents[$0.path] } == nil)
                Divider()
                Button("Rescan Current Folder", action: model.refreshFolder).keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.busy || model.currentFolder == nil || model.showingWelcome)
                Button("Show Selection in Finder") {
                    if let path = model.selectedPath ?? model.currentFolder?.path { model.finder(path) }
                }.keyboardShortcut("r").disabled(model.showingWelcome || model.snapshot == nil)
            }
        }
    }

    private var previewAppearance: ColorScheme? {
        switch ProcessInfo.processInfo.environment["DISK_ASSESSMENT_APPEARANCE"] {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

@main struct DiskAssessmentApp {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--scan"), args.count > i + 1 {
            do {
                let rules = Bundle.main.resourceURL?.appendingPathComponent("cleanup-rules.json")
                    ?? URL(fileURLWithPath: "resources/cleanup-rules.json")
                let scanner = try DiskScanner(root: args[i + 1], rulesURL: rules, cancellation: ScanCancellation())
                let result = try JSONEncoder().encode(scanner.run())
                if let output = args.firstIndex(of: "--output"), args.count > output + 1 {
                    try result.write(to: URL(fileURLWithPath: args[output + 1]), options: .atomic)
                } else { FileHandle.standardOutput.write(result) }
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        } else { NativeAssessmentApp.main() }
    }
}
