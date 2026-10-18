import AppKit
import LaunchpadCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct LaunchpadNativeApp: App {
    @NSApplicationDelegateAdaptor(LaunchpadAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class LaunchpadAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel?
    private var store: LaunchpadStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let store = LaunchpadStore()
        self.store = store

        let panel = LaunchpadPanel(
            contentRect: screenUnderPointer().frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.worksWhenModal = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LaunchpadView(store: store))
        self.panel = panel

        store.dismissAction = { [weak panel] in
            panel?.orderOut(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let panel else { return }
        panel.setFrame(screenUnderPointer().frame, display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        if let panel {
            panel.setFrame(screenUnderPointer().frame, display: true)
            panel.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func screenUnderPointer() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private final class LaunchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct LaunchpadView: View {
    @ObservedObject var store: LaunchpadStore
    @State private var searchText = ""
    @State private var currentFolderPath: String?
    @State private var currentManualGroupID: String?
    @State private var tileFrames: [String: CGRect] = [:]
    @State private var isGroupExitTargeted = false
    @State private var folderTitle = ""
    @State private var groupToRename: ManualGroup?
    @State private var renameText = ""
    @FocusState private var searchFocused: Bool

    private let gridColumnSpacing: CGFloat = 28
    private let minimumGridColumnWidth: CGFloat = 112
    private let maximumGridColumnCount = 8

    private var entries: [AppEntry] {
        store.entries(in: currentFolderPath, manualGroupID: currentManualGroupID, query: searchText)
    }

    private var searchField: some View {
        ZStack(alignment: .leading) {
            if searchText.isEmpty {
                Text("搜索应用...")
                    .foregroundStyle(.white.opacity(0.9))
                    .allowsHitTesting(false)
            }
            TextField("", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onExitCommand(perform: handleEscape)
                .onSubmit(launchFirstMatch)
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.06)
                .opacity(0.94)

            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    Spacer()

                    if !folderTitle.isEmpty {
                        Text(folderTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .frame(maxWidth: 1360)

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.52))
                    searchField
                }
                .padding(.horizontal, 15)
                .frame(width: 360, height: 40)
                .background(.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))

                GeometryReader { scrollArea in
                    ScrollView {
                        if entries.isEmpty && !store.apps.isEmpty {
                            Text("没有匹配的应用")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.65))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 52)
                        } else {
                            LazyVGrid(columns: gridColumns(for: scrollArea.size.width), spacing: 25) {
                                ForEach(entries) { entry in
                                    AppTile(
                                        entry: entry,
                                        store: store,
                                        isDraggable: searchText.isEmpty,
                                        onOpen: { open(entry) },
                                        onGroupDrop: { providers in
                                            handleGroupDrop(providers, onto: entry)
                                        },
                                        onRename: { group in
                                            groupToRename = group
                                            renameText = group.name
                                        }
                                    )
                                }
                            }
                            .frame(maxWidth: 1332)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: scrollArea.size.height, alignment: .top)
                            .coordinateSpace(name: "app-grid")
                            .onPreferenceChange(TileFramePreferenceKey.self) { tileFrames = $0 }
                            .onDrop(of: [UTType.plainText], isTargeted: nil) { providers, location in
                                handleDrop(providers, at: location)
                            }
                            .background {
                                backgroundTapTarget
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .background {
                        backgroundTapTarget
                    }
                }
                .frame(maxWidth: 1440)

                if store.apps.isEmpty {
                    ProgressView("正在扫描应用...")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 34)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                backgroundTapTarget
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
        .overlay(alignment: .trailing) {
            if currentManualGroupID != nil, store.draggedPath != nil {
                groupExitDropTarget
                    .padding(.trailing, 36)
                    .transition(.opacity)
            }
        }
        .onAppear {
            searchFocused = true
        }
        .onExitCommand(perform: handleEscape)
        .alert("重命名分组", isPresented: Binding(
            get: { groupToRename != nil },
            set: { if !$0 { groupToRename = nil } }
        )) {
            TextField("分组名称", text: $renameText)
            Button("取消", role: .cancel) { groupToRename = nil }
            Button("保存") {
                if let groupToRename {
                    store.renameGroup(groupToRename.id, to: renameText)
                }
                groupToRename = nil
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.dismissError() } }
        )) {
            Button("好", role: .cancel) { store.dismissError() }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func gridColumns(for availableWidth: CGFloat) -> [GridItem] {
        let gridWidth = min(max(availableWidth - 56, 0), 1332)
        let columnCount = min(
            maximumGridColumnCount,
            max(1, Int((gridWidth + gridColumnSpacing) / (minimumGridColumnWidth + gridColumnSpacing)))
        )
        return Array(
            repeating: GridItem(.flexible(minimum: minimumGridColumnWidth, maximum: 142), spacing: gridColumnSpacing, alignment: .top),
            count: columnCount
        )
    }

    private func open(_ entry: AppEntry) {
        switch entry.kind {
        case .application:
            guard let app = entry.app else { return }
            store.dismiss()
            store.open(app)
        case .folder:
            currentFolderPath = entry.path
            currentManualGroupID = entry.manualGroupID
            folderTitle = entry.name
            searchText = ""
        }
    }

    private func showRoot() {
        currentFolderPath = nil
        currentManualGroupID = nil
        folderTitle = ""
        searchText = ""
    }

    private func removeDraggedAppFromCurrentGroup(_ providers: [NSItemProvider]) -> Bool {
        guard let groupID = currentManualGroupID,
              !providers.isEmpty,
              let draggedPath = store.draggedPath else { return false }
        store.removeFromGroup(draggedPath, groupID: groupID)
        store.draggedPath = nil
        showRoot()
        return true
    }

    private var groupExitDropTarget: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.right.to.line")
                .font(.system(size: 25, weight: .medium))
            Text("移出分组")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white.opacity(isGroupExitTargeted ? 1 : 0.82))
        .frame(width: 132, height: 150)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.white.opacity(isGroupExitTargeted ? 0.16 : 0.07))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    .white.opacity(isGroupExitTargeted ? 0.95 : 0.5),
                    style: StrokeStyle(lineWidth: isGroupExitTargeted ? 2 : 1.5, dash: [7, 5])
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onDrop(of: [UTType.plainText], isTargeted: $isGroupExitTargeted) { providers in
            removeDraggedAppFromCurrentGroup(providers)
        }
    }

    private func handleBackgroundTap() {
        if currentFolderPath != nil || currentManualGroupID != nil {
            showRoot()
        } else {
            store.dismiss()
        }
    }

    private var backgroundTapTarget: some View {
        Button(action: handleBackgroundTap) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleEscape() {
        if currentFolderPath != nil || currentManualGroupID != nil {
            showRoot()
        } else {
            store.dismiss()
        }
    }

    private func launchFirstMatch() {
        guard currentFolderPath == nil,
              currentManualGroupID == nil,
              let app = entries.first?.app else { return }
        store.dismiss()
        store.open(app)
    }

    private func handleDrop(_ providers: [NSItemProvider], at location: CGPoint) -> Bool {
        guard searchText.isEmpty, let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, error in
            DispatchQueue.main.async {
                defer { store.draggedPath = nil }
                if let error {
                    store.errorMessage = "无法读取拖动的应用：\(error.localizedDescription)"
                    return
                }
                guard let sourcePath = object as? String else {
                    store.errorMessage = "无法识别拖动的应用。"
                    return
                }
                applyDrop(sourcePath, at: location)
            }
        }
        return true
    }

    private func applyDrop(_ sourcePath: String, at location: CGPoint) {
        let paths = entries.map(\.path)
        guard !paths.isEmpty else { return }

        guard let insertionIndex = insertionIndex(at: location, paths: paths) else { return }
        reorder(sourcePath, at: insertionIndex, paths: paths)
    }

    private func handleGroupDrop(_ providers: [NSItemProvider], onto target: AppEntry) -> Bool {
        guard searchText.isEmpty,
              currentManualGroupID == nil,
              !providers.isEmpty,
              let sourcePath = store.draggedPath,
              sourcePath != target.path else { return false }
        store.createGroup(with: sourcePath, and: target.path, context: currentFolderPath)
        store.draggedPath = nil
        return true
    }

    private func insertionIndex(at point: CGPoint, paths: [String]) -> Int? {
        let visibleFrames = paths.enumerated().compactMap { index, path -> (Int, CGRect)? in
            guard let frame = tileFrames[path] else { return nil }
            return (index, frame)
        }
        guard !visibleFrames.isEmpty else { return nil }

        let adjacentGaps = zip(visibleFrames, visibleFrames.dropFirst()).compactMap { pair -> (Int, CGFloat)? in
            let (left, right) = pair
            guard right.0 == left.0 + 1 else { return nil }
            let midpoint = CGPoint(
                x: (left.1.midX + right.1.midX) / 2,
                y: (left.1.midY + right.1.midY) / 2
            )
            let dx = point.x - midpoint.x
            let dy = point.y - midpoint.y
            return (right.0, dx * dx + dy * dy)
        }
        if let closestGap = adjacentGaps.min(by: { $0.1 < $1.1 }) {
            return closestGap.0
        }

        guard let nearest = visibleFrames.min(by: {
            distanceSquared(from: point, to: $0.1) < distanceSquared(from: point, to: $1.1)
        }) else {
            return nil
        }
        let frame = nearest.1
        let after = abs(point.x - frame.midX) > abs(point.y - frame.midY)
            ? point.x > frame.midX
            : point.y > frame.midY
        return nearest.0 + (after ? 1 : 0)
    }

    private func distanceSquared(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(max(frame.minX - point.x, 0), point.x - frame.maxX)
        let dy = max(max(frame.minY - point.y, 0), point.y - frame.maxY)
        return dx * dx + dy * dy
    }

    private func reorder(_ sourcePath: String, at index: Int, paths: [String]) {
        store.reorder(
            paths,
            moving: sourcePath,
            to: index,
            context: currentFolderPath,
            manualGroupID: currentManualGroupID
        )
    }
}

private struct TileFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct AppTile: View {
    let entry: AppEntry
    @ObservedObject var store: LaunchpadStore
    let isDraggable: Bool
    let onOpen: () -> Void
    let onGroupDrop: ([NSItemProvider]) -> Bool
    let onRename: (ManualGroup) -> Void
    @State private var isEditingGroupName = false
    @State private var groupName = ""
    @FocusState private var groupNameFocused: Bool

    var body: some View {
        VStack(spacing: 9) {
            Button(action: onOpen) {
                ZStack {
                    if entry.kind == .folder {
                        RoundedRectangle(cornerRadius: 17)
                            .fill(.white.opacity(0.085))
                            .overlay {
                                if entry.manualGroupID != nil {
                                    RoundedRectangle(cornerRadius: 17)
                                        .stroke(
                                            .white.opacity(0.55),
                                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 17)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                }
                            }
                            .frame(width: 75, height: 75)
                        LazyVGrid(columns: [GridItem(.fixed(23)), GridItem(.fixed(23))], spacing: 5) {
                            ForEach(Array(store.children(of: entry).prefix(4))) { app in
                                Image(nsImage: store.icon(for: app.path))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 23, height: 23)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                        .frame(width: 52, height: 52)
                    } else if let app = entry.app {
                        Image(nsImage: store.icon(for: app.path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 86, height: 86)
                    }
                }
                .frame(width: 96, height: 96)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Group {
                if isEditingGroupName {
                    TextField("分组名称", text: $groupName)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 108)
                        .focused($groupNameFocused)
                        .onSubmit(saveGroupName)
                        .onExitCommand(perform: cancelGroupNameEdit)
                        .onChange(of: groupNameFocused) { focused in
                            if !focused && isEditingGroupName {
                                saveGroupName()
                            }
                        }
                        .onAppear {
                            groupNameFocused = true
                        }
                } else if entry.manualGroupID != nil {
                    Text(entry.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 108)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2, perform: beginGroupNameEdit)
                } else {
                    Button(action: onOpen) {
                        Text(entry.name)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 108)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 122)
        }
        .frame(width: 122, height: 132)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            if let groupID = entry.manualGroupID,
               let group = store.groups.first(where: { $0.id == groupID }) {
                Button("重命名分组") { onRename(group) }
            }
        }
        .onDrag {
            guard isDraggable else { return NSItemProvider() }
            store.draggedPath = entry.path
            return NSItemProvider(object: entry.path as NSString)
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil, perform: onGroupDrop)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TileFramePreferenceKey.self,
                    value: [entry.path: proxy.frame(in: .named("app-grid"))]
                )
            }
        }
    }

    private func beginGroupNameEdit() {
        groupName = entry.name
        isEditingGroupName = true
    }

    private func saveGroupName() {
        guard let groupID = entry.manualGroupID else { return }
        store.renameGroup(groupID, to: groupName)
        isEditingGroupName = false
    }

    private func cancelGroupNameEdit() {
        isEditingGroupName = false
        groupNameFocused = false
    }
}
