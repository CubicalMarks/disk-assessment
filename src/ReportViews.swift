import SwiftUI
import AppKit

extension ScanNode: Identifiable { var id: String { path } }
extension Candidate: Identifiable { var id: String { path } }

private let mapColors: [Color] = [.blue, .indigo, .teal, .purple, .cyan, .mint, .pink, .orange]
private func itemColor(_ node: ScanNode) -> Color {
    node.kind == "other" ? .gray : mapColors[StorageMap.paletteIndex(node.path)]
}
private func tileInk(_ node: ScanNode) -> Color {
    let bright = [2, 4, 5, 7].contains(StorageMap.paletteIndex(node.path))
    return node.kind != "other" && bright ? Color(red: 0.04, green: 0.12, blue: 0.19) : .white
}
private func itemSymbol(_ node: ScanNode) -> String {
    node.kind == "directory" ? "folder.fill" : node.kind == "other" ? "square.stack.3d.up" : "doc.fill"
}

struct AssessmentView: View {
    @ObservedObject var model: AssessmentModel
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(ReportSection.allCases, selection: $model.section) { section in
                    Label(section.rawValue, systemImage: section.symbol).tag(section)
                        .padding(.vertical, 4)
                }.listStyle(.sidebar).disabled(model.snapshot == nil || model.showingWelcome || model.busy)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 9) {
                    Label("Read only", systemImage: "lock.shield").font(.body.weight(.medium))
                    Text("Filenames and sizes only.\nYour files stay untouched.").foregroundStyle(ReportTheme.muted)
                    if let snapshot = model.snapshot {
                        Divider()
                        Text("Original scan").foregroundStyle(ReportTheme.muted)
                        Text(ReportFormat.date(snapshot.scanned_at)).textSelection(.enabled)
                        if !(snapshot.folder_refreshes ?? []).isEmpty {
                            Label("Includes folder refreshes", systemImage: "arrow.clockwise").foregroundStyle(ReportTheme.muted)
                        }
                    }
                }.font(.system(size: 12)).padding(18)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 250)
        } detail: {
            Group {
                if model.busy && !model.refreshing { ScanProgressView(model: model) }
                else if model.showingWelcome || model.snapshot == nil { WelcomeView(model: model) }
                else {
                    switch model.section ?? .overview {
                    case .overview: OverviewView(model: model)
                    case .explore: ExplorerView(model: model)
                    case .review: ReviewView(model: model)
                    case .largest: LargestFilesView(model: model)
                    case .coverage: CoverageView(model: model)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ReportTheme.background)
                .navigationTitle(model.showingWelcome ? "Disk Assessment" : (model.section ?? .overview).rawValue)
                .toolbar {
                    ToolbarItemGroup {
                        if !model.showingWelcome, model.snapshot != nil {
                            Button(action: model.newScan) { Label("New Scan", systemImage: "plus") }.disabled(model.busy)
                            Button(action: model.export) { Label("Export Snapshot", systemImage: "square.and.arrow.up") }.disabled(model.busy)
                        }
                        Button(action: model.chooseFolder) { Label("Choose Folder", systemImage: "folder.badge.plus") }.disabled(model.busy)
                    }
                }
        }.font(.system(size: 13)).tint(ReportTheme.accent).accentColor(ReportTheme.accent)
            .alert("Disk Assessment", isPresented: $model.showingMessage) { Button("OK", role: .cancel) {} }
                message: { Text(model.message ?? "") }
    }
}

private struct WelcomeView: View {
    @ObservedObject var model: AssessmentModel
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 100, height: 100)
            VStack(spacing: 10) {
                Text("A little clarity for your storage.").font(.system(size: 30, weight: .semibold))
                Text("Explore what’s using space, find the big things,\nand decide what deserves a closer look.")
                    .font(.system(size: 16)).foregroundStyle(ReportTheme.muted).multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Scan Mac", action: model.scanMac).buttonStyle(.borderedProminent).controlSize(.large)
                Button("Choose Folder…", action: model.chooseFolder).controlSize(.large)
            }
            if model.snapshot != nil { Button("View last report", action: model.report).buttonStyle(.link) }
            Label("Private by design. Nothing deleted.", systemImage: "lock.shield").foregroundStyle(ReportTheme.muted)
            Text("Protected folders may be skipped and will appear in the report.")
                .font(.system(size: 12)).foregroundStyle(ReportTheme.muted)
            Spacer()
        }.padding(32).frame(maxWidth: .infinity)
    }
}

private struct ScanProgressView: View {
    @ObservedObject var model: AssessmentModel
    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text(model.refreshing ? "Refreshing this folder…" : "Reading storage…").font(.title2.weight(.semibold))
            Text(model.scanRoot ?? "").foregroundStyle(ReportTheme.muted).lineLimit(2).truncationMode(.middle)
            Text("\(model.progressFiles.formatted()) files · \(model.progressDirectories.formatted()) folders").monospacedDigit()
            Text(model.progressPath.isEmpty ? "Starting scan…" : model.progressPath)
                .font(.system(size: 12)).foregroundStyle(ReportTheme.muted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 460)
            Button(model.cancelling ? "Cancelling…" : model.refreshing ? "Cancel Rescan" : "Cancel Scan", action: model.cancel)
                .disabled(model.cancelling).keyboardShortcut(.cancelAction)
            Text("Reading filenames and sizes. File contents are never opened.")
                .font(.system(size: 12)).foregroundStyle(ReportTheme.muted)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReportHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 28, weight: .semibold))
            Text(subtitle).foregroundStyle(ReportTheme.muted).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReportCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(ReportTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(ReportTheme.line))
    }
}

private struct OverviewView: View {
    @ObservedObject var model: AssessmentModel
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), alignment: .top), count: 3) }
    var body: some View {
        if let snapshot = model.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ReportHeading(title: "Room to understand.", subtitle: snapshot.tree.path)
                    ReportCard {
                        HStack(alignment: .center, spacing: 24) {
                            ZStack {
                                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                                Circle().trim(from: 0, to: max(0, min(1, Double(snapshot.volume.free) / Double(max(1, snapshot.volume.total)))))
                                    .stroke(ReportTheme.ring, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                                Image(systemName: "internaldrive").font(.system(size: 28)).foregroundStyle(ReportTheme.ring)
                            }.frame(width: 94, height: 94).padding(5).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Available on volume").foregroundStyle(ReportTheme.muted)
                                Text(ReportFormat.bytes(snapshot.volume.free)).font(.system(size: 34, weight: .semibold)).monospacedDigit()
                                Text("of \(ReportFormat.bytes(snapshot.volume.total)) shared capacity").foregroundStyle(ReportTheme.muted)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    VolumeBar(snapshot: snapshot)
                    LazyVGrid(columns: columns, spacing: 16) {
                        metric("Files measured", value: ReportFormat.bytes(snapshot.tree.bytes), note: "\(snapshot.tree.files.formatted()) files · allocated blocks", symbol: "doc.on.doc")
                        metric("Rebuildable candidates", value: ReportFormat.bytes(snapshot.candidates.filter { $0.category == "rebuildable" }.reduce(0) { $0 + $1.bytes }), note: "Review first · rebuilds and downloads required", symbol: "arrow.triangle.2.circlepath", color: ReportTheme.green)
                        metric("Needs a closer look", value: ReportFormat.bytes(snapshot.candidates.filter { $0.category != "rebuildable" }.reduce(0) { $0 + $1.bytes }), note: "May include work, settings or personal data", symbol: "magnifyingglass", color: ReportTheme.orange)
                    }
                    HStack(spacing: 12) {
                        Button { model.section = .explore } label: { Label("Explore Storage Map", systemImage: "square.grid.2x2") }.buttonStyle(.borderedProminent)
                        Button { model.section = .review } label: { Label("Review Candidates", systemImage: "checklist") }
                    }.controlSize(.large)
                    ReportCard {
                        Label("A footprint is a starting point.", systemImage: "info.circle").font(.headline)
                        Text("Candidate sizes are review leads, never guaranteed reclaimable space. APFS sharing, snapshots and inaccessible folders can prevent an exact match with physical disk usage.")
                            .foregroundStyle(ReportTheme.muted).padding(.top, 5)
                        if snapshot.coverage.error_count > 0 {
                            Button("\(snapshot.coverage.error_count.formatted()) access issues · View scan details") { model.section = .coverage }.buttonStyle(.link).padding(.top, 8)
                        }
                        if !(snapshot.folder_refreshes ?? []).isEmpty {
                            Text("Includes folder refreshes. Other folders retain their original measurements; see Scan Details for dates and coverage limits.").foregroundStyle(ReportTheme.muted).padding(.top, 8)
                        }
                    }
                }.padding(30).frame(maxWidth: 1100)
            }
        }
    }
    private func metric(_ title: String, value: String, note: String, symbol: String, color: Color = ReportTheme.accent) -> some View {
        ReportCard {
            Label(title, systemImage: symbol).foregroundStyle(ReportTheme.muted)
            Text(value).font(.system(size: 25, weight: .semibold)).monospacedDigit().padding(.vertical, 5).foregroundStyle(color)
            Text(note).font(.system(size: 12)).foregroundStyle(ReportTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct VolumeBar: View {
    let snapshot: Snapshot
    private var parts: [(String, Int64, Color)] {
        [("Measured file blocks", snapshot.tree.bytes, ReportTheme.accent),
         ("Usage not attributed by scan", max(0, snapshot.volume.used - snapshot.tree.bytes), ReportTheme.gap),
         ("Other shared usage", snapshot.volume.other_shared_usage, ReportTheme.shared),
         ("Available", snapshot.volume.free, ReportTheme.available)]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(parts.indices, id: \.self) { i in
                        let part = parts[i]
                        Rectangle().fill(part.2).frame(width: proxy.size.width * Double(max(0, part.1)) / max(1, parts.reduce(0.0) { $0 + Double(max(0, $1.1)) }))
                            .help("\(part.0): \(ReportFormat.bytes(part.1))")
                    }
                }.clipShape(Capsule())
            }.frame(height: 12).accessibilityLabel("Volume usage")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(parts.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        Circle().fill(parts[i].2).frame(width: 7, height: 7)
                        Text(parts[i].0).font(.system(size: 12)).foregroundStyle(ReportTheme.muted)
                    }
                }
            }
            if snapshot.tree.bytes > snapshot.volume.used {
                Text("Measured blocks exceed volume-used bytes; this bar shows scan accounting.").font(.system(size: 12)).foregroundStyle(ReportTheme.muted)
            }
        }
    }
}

private struct ExplorerView: View {
    @ObservedObject var model: AssessmentModel
    @State private var filter = ""
    @State private var mapMode = true
    @State private var balanced = true
    @State private var sortOrder = [KeyPathComparator(\ScanNode.bytes, order: .reverse)]
    private var nodes: [ScanNode] {
        guard let folder = model.currentFolder, let index = model.index else { return [] }
        return index.children(of: folder).filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }.sorted(using: sortOrder)
    }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                navigation
                if let folder = model.currentFolder, let snapshot = model.snapshot {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ReportFormat.bytes(folder.bytes)).font(.title2.weight(.semibold)).monospacedDigit()
                        Text("allocated · \(folder.files.formatted()) files").foregroundStyle(ReportTheme.muted)
                        Spacer()
                        Button { model.finder(folder.path, openFolder: true) } label: { Image(systemName: "folder") }.help("Open current folder in Finder").accessibilityLabel("Open current folder in Finder")
                        Button(action: model.refreshFolder) { Image(systemName: "arrow.clockwise") }.help("Rescan this folder").accessibilityLabel("Rescan current folder")
                    }.disabled(model.busy)
                    FlowLayout(spacing: 10) {
                        TextField("Filter this folder", text: $filter).textFieldStyle(.roundedBorder).frame(width: 210)
                        Picker("View", selection: $mapMode) {
                            Image(systemName: "square.grid.2x2").tag(true)
                            Image(systemName: "list.bullet").tag(false)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 90)
                        if mapMode {
                            Picker("Scale", selection: $balanced) { Text("Balanced").tag(true); Text("Actual size").tag(false) }
                                .frame(width: 175)
                        }
                    }.disabled(model.busy)
                    ZStack {
                        if nodes.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "folder").font(.largeTitle).foregroundStyle(ReportTheme.muted)
                                Text(filter.isEmpty ? "No entries to display" : "No matching entries").font(.headline)
                                Text("Report detail starts at \(ReportFormat.bytes(snapshot.coverage.tree_minimum_bytes)).").foregroundStyle(ReportTheme.muted)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if mapMode { map }
                        else { fileTable }
                        if model.refreshing {
                            ScanProgressView(model: model).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    VStack(alignment: .leading, spacing: 5) {
                        Text(mapMode && balanced ? "Balanced areas keep smaller entries visible. Labels and percentages show measured bytes." : mapMode ? "Areas, labels and percentages use measured allocated bytes." : "Sizes and percentages use measured allocated bytes.")
                        Text("\(ReportFormat.bytes(snapshot.coverage.tree_minimum_bytes)) detail · Select an item to inspect; double-click a folder to explore.")
                        if let refreshed = snapshot.folder_refreshes?.last(where: { $0.path == folder.path }) {
                            Text("This folder refreshed \(ReportFormat.date(refreshed.scanned_at)). Other folders retain their original age.")
                        }
                    }.font(.system(size: 12)).foregroundStyle(ReportTheme.muted)
                }
            }.padding(24).frame(minWidth: 480)
            ItemInspector(model: model).frame(minWidth: 220, idealWidth: 255, maxWidth: 310)
        }
        .onChange(of: model.currentFolder?.path) { _ in filter = "" }
    }
    private var navigation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: model.back) { Image(systemName: "chevron.left") }.disabled(model.navigation?.canBack != true).help("Back")
                Button(action: model.forward) { Image(systemName: "chevron.right") }.disabled(model.navigation?.canForward != true).help("Forward")
                Button(action: model.up) { Image(systemName: "arrow.up") }.disabled(model.currentFolder.flatMap { model.index?.parents[$0.path] } == nil).help("Enclosing folder")
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    if let folder = model.currentFolder, let chain = model.index?.chain(folder.path) {
                        ForEach(chain) { node in
                            if node.path != chain.first?.path { Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.tertiary) }
                            Button(node.path == model.snapshot?.tree.path && node.path == "/" ? "Data volume" : node.name) { model.visit(node.path) }
                                .buttonStyle(.link).help(node.path)
                        }
                    }
                }
            }
        }.disabled(model.busy)
    }
    private var map: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(StorageMap.layout(nodes, in: CGRect(origin: .zero, size: proxy.size), balanced: balanced)) { tile in
                    MapTileView(node: tile.node, width: tile.rect.width, height: tile.rect.height,
                        total: model.currentFolder?.bytes ?? 0, selected: model.selectedPath == tile.id,
                        select: { model.select(tile.node) }, open: { if tile.node.kind == "directory" { model.visit(tile.id) } })
                        .contextMenu { ItemActions(model: model, node: tile.node) }
                        .position(x: tile.rect.midX, y: tile.rect.midY)
                }
            }
        }.disabled(model.busy)
    }
    private var fileTable: some View {
        Table(nodes, selection: $model.selectedPath, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { node in
                Label(node.name, systemImage: itemSymbol(node)).foregroundStyle(itemColor(node))
                    .contextMenu { ItemActions(model: model, node: node) }
                    .onTapGesture(count: 2) { if node.kind == "directory" { model.visit(node.path) } }
            }
            TableColumn("Allocated", value: \.bytes) { node in Text(ReportFormat.bytes(node.bytes)).monospacedDigit() }.width(95)
            TableColumn("Share") { node in Text(ReportFormat.percent(node.bytes, of: model.currentFolder?.bytes ?? 0)).foregroundStyle(ReportTheme.muted) }.width(65)
        }.disabled(model.busy)
    }
}

// Lay out each native control once, wrapping at narrow window widths.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (CGSize, [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        var origins: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), origins)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .greatestFiniteMagnitude).0
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = arrange(subviews, width: bounds.width).1
        for (i, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + origins[i].x, y: bounds.minY + origins[i].y), anchor: .topLeading, proposal: .unspecified)
        }
    }
}

private struct MapTileView: View {
    let node: ScanNode
    let width: CGFloat
    let height: CGFloat
    let total: Int64
    let selected: Bool
    let select: () -> Void
    let open: () -> Void
    var body: some View {
        Button(action: select) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7).fill(itemColor(node).gradient)
                if width > 65 && height > 40 {
                    VStack(alignment: .leading, spacing: 6) {
                        if height > 85 { Image(systemName: itemSymbol(node)).font(.system(size: 18)) }
                        Text(node.name).font(.system(size: 13, weight: .semibold)).lineLimit(height > 90 ? 2 : 1)
                        if height > 60 { Text(ReportFormat.bytes(node.bytes)).font(.system(size: 12)).monospacedDigit() }
                        if height > 130 { Text(ReportFormat.percent(node.bytes, of: total)).font(.system(size: 12)).opacity(0.85) }
                        Spacer(minLength: 0)
                    }.padding(12).foregroundStyle(tileInk(node))
                }
            }.overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.white.opacity(0.95) : Color.clear, lineWidth: 3))
        }.buttonStyle(.plain).padding(2).frame(width: max(0, width), height: max(0, height)).clipped()
            .simultaneousGesture(TapGesture(count: 2).onEnded(open))
            .help("\(node.name)\n\(ReportFormat.bytes(node.bytes)) allocated · \(ReportFormat.percent(node.bytes, of: total))\n\(node.kind == "other" ? "Below the report detail threshold" : node.path)")
            .accessibilityLabel("\(node.name), \(ReportFormat.bytes(node.bytes)), \(ReportFormat.percent(node.bytes, of: total))")
            .accessibilityActions {
                if node.kind == "directory" { Button("Explore folder", action: open) }
            }
    }
}

private struct ItemActions: View {
    @ObservedObject var model: AssessmentModel
    let node: ScanNode
    var body: some View {
        if node.kind == "directory" { Button("Explore Folder") { model.visit(node.path) } }
        if node.kind != "other" {
            Button("Show in Finder") { model.finder(node.path) }
            if node.kind == "directory" { Button("Open in Finder") { model.finder(node.path, openFolder: true) } }
            Divider()
            Button("Copy Path") { model.copy([node.path]) }
        }
    }
}

private struct ItemInspector: View {
    @ObservedObject var model: AssessmentModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let node = model.selectedNode {
                    Image(systemName: itemSymbol(node)).font(.system(size: 32)).foregroundStyle(itemColor(node))
                    Text(node.name).font(.title3.weight(.semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text(ReportFormat.bytes(node.bytes)).font(.title.weight(.semibold)).monospacedDigit()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Allocated blocks").foregroundStyle(ReportTheme.muted)
                        if node.kind != "candidate" { Text("\(ReportFormat.bytes(node.logical_bytes)) logical size").foregroundStyle(ReportTheme.muted) }
                        Text("\(node.files.formatted()) files").foregroundStyle(ReportTheme.muted)
                    }
                    Divider()
                    if node.kind == "other" {
                        Text("Entries below the report detail threshold. This group has no single Finder location.").foregroundStyle(ReportTheme.muted)
                    } else {
                        Text(node.path).font(.system(size: 12)).foregroundStyle(ReportTheme.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        if node.kind == "directory" { Button("Explore Folder") { model.visit(node.path) }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: []) }
                        Button("Show in Finder") { model.finder(node.path) }
                        Button("Copy Path") { model.copy([node.path]) }
                    }
                    if node.errors > 0 { Label("Includes inaccessible entries", systemImage: "exclamationmark.triangle").foregroundStyle(ReportTheme.orange) }
                    if let candidate = model.snapshot?.candidates.first(where: { $0.path == node.path }) {
                        Divider()
                        Text(candidate.label).font(.headline)
                        Text(candidate.guidance).foregroundStyle(ReportTheme.muted)
                        Text("Review lead, not guaranteed reclaimable space.").font(.system(size: 12)).foregroundStyle(ReportTheme.muted)
                    }
                } else {
                    Image(systemName: "cursorarrow.click").font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text("Take a closer look").font(.headline)
                    Text("Select an item to see its measured footprint and location.").foregroundStyle(ReportTheme.muted)
                }
                Spacer(minLength: 0)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }.background(ReportTheme.surface)
    }
}

private struct ReviewView: View {
    @ObservedObject var model: AssessmentModel
    @State private var search = ""
    @State private var category = "all"
    private var candidates: [Candidate] {
        (model.snapshot?.candidates ?? []).filter {
            (category == "all" || $0.category == category) && (search.isEmpty || $0.path.localizedCaseInsensitiveContains(search) || $0.label.localizedCaseInsensitiveContains(search))
        }.sorted { $0.bytes > $1.bytes }
    }
    private var selected: [Candidate] { (model.snapshot?.candidates ?? []).filter { model.reviewedPaths.contains($0.path) } }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 18) {
                ReportHeading(title: "Worth a closer look.", subtitle: "Candidates ordered by allocated footprint. Review before making changes in Finder.")
                HStack {
                    TextField("Find a path or category", text: $search).textFieldStyle(.roundedBorder)
                    Picker("Category", selection: $category) {
                        Text("All candidates").tag("all")
                        Text("Rebuildable").tag("rebuildable")
                        Text("Needs review").tag("review")
                    }.labelsHidden().frame(width: 170)
                }
                if candidates.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checklist").font(.largeTitle).foregroundStyle(ReportTheme.muted)
                        Text(search.isEmpty && category == "all" ? "No candidates in this report" : "No matching candidates").font(.headline)
                        Text("Candidate rules cover specific locations; this does not establish that everything else is needed.").foregroundStyle(ReportTheme.muted).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $model.selectedPath) {
                        ForEach(candidates) { candidate in
                            HStack(alignment: .top, spacing: 12) {
                                Toggle("Select \(candidate.label)", isOn: Binding(get: { model.reviewedPaths.contains(candidate.path) }, set: { value in
                                    if value { model.reviewedPaths.insert(candidate.path) } else { model.reviewedPaths.remove(candidate.path) }
                                })).toggleStyle(.checkbox).labelsHidden().padding(.top, 3)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(candidate.label).font(.headline)
                                        Spacer()
                                        Text(ReportFormat.bytes(candidate.bytes)).font(.body.weight(.semibold)).monospacedDigit()
                                    }
                                    Text(candidate.path).font(.system(size: 12)).foregroundStyle(ReportTheme.muted).lineLimit(1).truncationMode(.middle)
                                    HStack {
                                        Label(candidate.category == "rebuildable" ? "Rebuildable" : "Needs review", systemImage: candidate.category == "rebuildable" ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                                        if candidate.incomplete { Label("Incomplete", systemImage: "exclamationmark.triangle") }
                                    }.font(.system(size: 12)).foregroundStyle(ReportTheme.muted)
                                }
                            }.padding(.vertical, 8).tag(candidate.path)
                                .contextMenu {
                                    Button("Show in Finder") { model.finder(candidate.path) }
                                    Button("Copy Path") { model.copy([candidate.path]) }
                                }
                        }
                    }.listStyle(.inset(alternatesRowBackgrounds: true))
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(selected.count) selected · \(ReportFormat.bytes(selected.reduce(0) { $0 + $1.bytes }))").font(.body.weight(.medium))
                        Text("Selection collects paths for review. Nothing is deleted.").font(.system(size: 12)).foregroundStyle(ReportTheme.muted)
                    }
                    Spacer()
                    Button("Copy Selected Paths") { model.copy(selected.map(\.path)) }.disabled(selected.isEmpty)
                }
            }.padding(24).frame(minWidth: 480)
            ItemInspector(model: model).frame(minWidth: 220, idealWidth: 255, maxWidth: 310)
        }
    }
}

private struct LargestFilesView: View {
    @ObservedObject var model: AssessmentModel
    @State private var search = ""
    @State private var sortOrder = [KeyPathComparator(\ScanNode.bytes, order: .reverse)]
    private var nodes: [ScanNode] {
        (model.snapshot?.largest_files ?? []).filter { search.isEmpty || $0.path.localizedCaseInsensitiveContains(search) }.sorted(using: sortOrder)
    }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 18) {
                ReportHeading(title: "The big things.", subtitle: (model.snapshot?.folder_refreshes ?? []).isEmpty ? "The largest files measured in this scan." : "Largest known files after folder refreshes. A full scan rebuilds the global ranking.")
                TextField("Find a file or path", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 350)
                Table(nodes, selection: $model.selectedPath, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { node in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(node.name, systemImage: "doc").lineLimit(1)
                            Text(node.path).font(.system(size: 12)).foregroundStyle(ReportTheme.muted).lineLimit(1).truncationMode(.middle)
                        }.padding(.vertical, 4).contextMenu { ItemActions(model: model, node: node) }
                    }
                    TableColumn("Allocated", value: \.bytes) { node in Text(ReportFormat.bytes(node.bytes)).monospacedDigit() }.width(100)
                    TableColumn("Logical", value: \.logical_bytes) { node in Text(ReportFormat.bytes(node.logical_bytes)).foregroundStyle(ReportTheme.muted).monospacedDigit() }.width(100)
                }
                Text("Allocated blocks can differ from logical size. Shared APFS data can prevent exact reclaim estimates.")
                    .font(.system(size: 12)).foregroundStyle(ReportTheme.muted)
            }.padding(24).frame(minWidth: 480)
            ItemInspector(model: model).frame(minWidth: 220, idealWidth: 255, maxWidth: 310)
        }
    }
}

private struct CoverageView: View {
    @ObservedObject var model: AssessmentModel
    var body: some View {
        if let snapshot = model.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ReportHeading(title: "What the numbers can tell you.", subtitle: "Original scan: \(ReportFormat.date(snapshot.scanned_at)) · \(snapshot.duration_seconds.formatted(.number.precision(.fractionLength(1)))) seconds")
                    ReportCard {
                        Text("Measurement & coverage").font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 12) {
                            GridRow { Text("Root").foregroundStyle(ReportTheme.muted); Text(snapshot.root).textSelection(.enabled) }
                            GridRow { Text("Files").foregroundStyle(ReportTheme.muted); Text(snapshot.coverage.files.formatted()) }
                            GridRow { Text("Folders").foregroundStyle(ReportTheme.muted); Text(snapshot.coverage.directories.formatted()) }
                            GridRow { Text("Symlinks skipped").foregroundStyle(ReportTheme.muted); Text(snapshot.coverage.symlinks_skipped.formatted()) }
                            GridRow { Text("Other devices skipped").foregroundStyle(ReportTheme.muted); Text(snapshot.coverage.mounts_skipped.count.formatted()) }
                            GridRow { Text("Access issues").foregroundStyle(ReportTheme.muted); Text(snapshot.coverage.error_count.formatted()) }
                            GridRow { Text("Tree detail threshold").foregroundStyle(ReportTheme.muted); Text(ReportFormat.bytes(snapshot.coverage.tree_minimum_bytes)) }
                        }.padding(.top, 14)
                        if !(snapshot.folder_refreshes ?? []).isEmpty {
                            Text("Folder, symlink and mount counters retain their original scan age. Hard links shared between refreshed and older folders may be counted differently. Run a full scan to reconcile them.")
                                .foregroundStyle(ReportTheme.muted).padding(.top, 14)
                        }
                    }
                    if let refreshes = snapshot.folder_refreshes, !refreshes.isEmpty {
                        ReportCard {
                            Text("Folder refreshes").font(.headline)
                            ForEach(refreshes, id: \.path) { refresh in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(refresh.path).textSelection(.enabled)
                                    Text(ReportFormat.date(refresh.scanned_at)).foregroundStyle(ReportTheme.muted)
                                }.padding(.top, 12)
                            }
                        }
                    }
                    ReportCard {
                        Text("How to read this report").font(.headline)
                        ForEach(Array(snapshot.method.enumerated()), id: \.offset) { _, method in
                            Text(method).foregroundStyle(ReportTheme.muted).padding(.top, 10)
                        }
                        Text("The scanner reads filenames and metadata only. It skips symlinks and other filesystem devices. APFS clones, compression, snapshots, directory metadata and inaccessible paths prevent exact reconciliation with physical usage or recoverable space.")
                            .foregroundStyle(ReportTheme.muted).padding(.top, 10)
                    }
                    if !snapshot.coverage.errors.isEmpty {
                        ReportCard {
                            Text("Access issues").font(.headline)
                            Text("Protected folders can be skipped. The app does not request administrator privileges or change Full Disk Access settings.").foregroundStyle(ReportTheme.muted).padding(.top, 5)
                            ForEach(Array(snapshot.coverage.errors.enumerated()), id: \.offset) { _, issue in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(issue.path).textSelection(.enabled)
                                    Text(issue.detail).font(.system(size: 12)).foregroundStyle(ReportTheme.muted)
                                }.padding(.top, 12)
                            }
                        }
                    }
                    if !snapshot.coverage.mounts_skipped.isEmpty {
                        ReportCard {
                            Text("Other filesystem devices skipped").font(.headline)
                            ForEach(snapshot.coverage.mounts_skipped, id: \.self) { path in Text(path).textSelection(.enabled).padding(.top, 6) }
                        }
                    }
                    ReportCard {
                        Text("System-managed storage").font(.headline)
                        Text("Use the owning tools to review these. Their estimates may overlap this report’s footprints.").foregroundStyle(ReportTheme.muted).padding(.top, 5)
                        Link("Apple: local snapshots", destination: URL(string: "https://support.apple.com/en-ie/102154")!).padding(.top, 10)
                        Link("Docker: disk image storage", destination: URL(string: "https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/")!)
                        Link("Apple: manage Xcode components", destination: URL(string: "https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components")!)
                    }
                }.padding(30).frame(maxWidth: 1100, alignment: .leading)
            }
        }
    }
}
