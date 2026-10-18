import AppKit
import Combine
import Foundation

public struct InstalledApp: Identifiable, Codable, Hashable, Sendable {
    public let name: String
    public let path: String

    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public struct ManualGroup: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var context: String?
    public var appPaths: [String]

    public init(id: String, name: String, context: String?, appPaths: [String]) {
        self.id = id
        self.name = name
        self.context = context
        self.appPaths = appPaths
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case context
        case appPaths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        context = try container.decodeIfPresent(String.self, forKey: .context)
        appPaths = try container.decode([String].self, forKey: .appPaths)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        if let context {
            try container.encode(context, forKey: .context)
        } else {
            try container.encodeNil(forKey: .context)
        }
        try container.encode(appPaths, forKey: .appPaths)
    }
}

public struct AppEntry: Identifiable {
    public enum Kind: Equatable {
        case application
        case folder
    }

    public let kind: Kind
    public let name: String
    public let path: String
    public let app: InstalledApp?
    public let children: [InstalledApp]
    public let manualGroupID: String?

    public var id: String { path }

    public static func application(_ app: InstalledApp) -> AppEntry {
        AppEntry(
            kind: .application,
            name: app.name,
            path: app.path,
            app: app,
            children: [],
            manualGroupID: nil
        )
    }

    public static func folder(
        name: String,
        path: String,
        children: [InstalledApp],
        manualGroupID: String? = nil
    ) -> AppEntry {
        AppEntry(
            kind: .folder,
            name: name,
            path: path,
            app: nil,
            children: children,
            manualGroupID: manualGroupID
        )
    }
}

public struct GroupingUpdate: Equatable {
    public let groups: [ManualGroup]
    public let group: ManualGroup
    public let order: [String]

    public init(groups: [ManualGroup], group: ManualGroup, order: [String]) {
        self.groups = groups
        self.group = group
        self.order = order
    }
}

public enum LaunchpadLogic {
    public static func parentDirectory(for appPath: String) -> String? {
        let parent = URL(fileURLWithPath: appPath).deletingLastPathComponent().path
        guard parent != "/Applications",
              parent != "/System/Applications",
              !parent.hasSuffix("/Applications"),
              !parent.hasSuffix("/System/Applications") else {
            return nil
        }
        return parent
    }

    public static func folderEntries(from apps: [InstalledApp]) -> [AppEntry] {
        var regularApps: [InstalledApp] = []
        var folders: [String: [InstalledApp]] = [:]
        var folderOrder: [String] = []

        for app in apps {
            guard let parent = parentDirectory(for: app.path) else {
                regularApps.append(app)
                continue
            }
            if folders[parent] == nil {
                folders[parent] = []
                folderOrder.append(parent)
            }
            folders[parent, default: []].append(app)
        }

        var entries = regularApps.map(AppEntry.application)
        for path in folderOrder {
            let children = folders[path, default: []]
            guard children.count > 1 else {
                entries.append(contentsOf: children.map(AppEntry.application))
                continue
            }
            entries.append(.folder(
                name: URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                children: children
            ))
        }
        return entries
    }

    public static func applyingManualGroups(
        to entries: [AppEntry],
        groups: [ManualGroup],
        apps: [InstalledApp],
        context: String?
    ) -> [AppEntry] {
        var result = entries

        for group in groups where group.context == context {
            let children = group.appPaths.compactMap { path in
                apps.first { $0.path == path }
            }
            guard children.count > 1 else { continue }

            let memberPaths = Set(children.map(\.path))
            var representedPaths = Set<String>()
            var updatedResult: [AppEntry] = []

            for entry in result {
                if memberPaths.contains(entry.path) {
                    representedPaths.insert(entry.path)
                    continue
                }

                guard entry.kind == .folder, !entry.children.isEmpty else {
                    updatedResult.append(entry)
                    continue
                }

                let groupedChildren = entry.children.filter { memberPaths.contains($0.path) }
                guard !groupedChildren.isEmpty else {
                    updatedResult.append(entry)
                    continue
                }

                representedPaths.formUnion(groupedChildren.map(\.path))
                if groupedChildren.count < entry.children.count {
                    updatedResult.append(contentsOf:
                        entry.children
                            .filter { !memberPaths.contains($0.path) }
                            .map(AppEntry.application)
                    )
                }
            }

            guard representedPaths == memberPaths else { continue }
            result = updatedResult
            result.append(.folder(
                name: group.name,
                path: "manual-folder:\(group.id)",
                children: children,
                manualGroupID: group.id
            ))
        }
        return result
    }

    public static func filtered(_ entries: [AppEntry], query: String) -> [AppEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(needle)
                || entry.path.localizedCaseInsensitiveContains(needle)
                || entry.children.contains {
                    $0.name.localizedCaseInsensitiveContains(needle)
                        || $0.path.localizedCaseInsensitiveContains(needle)
                }
        }
    }

    public static func ordered(_ entries: [AppEntry], paths: [String]) -> [AppEntry] {
        var positions: [String: Int] = [:]
        for (index, path) in paths.enumerated() where positions[path] == nil {
            positions[path] = index
        }
        return entries.enumerated().sorted { left, right in
            let leftPosition = positions[left.element.path]
            let rightPosition = positions[right.element.path]
            switch (leftPosition, rightPosition) {
            case let (leftPosition?, rightPosition?):
                return leftPosition == rightPosition ? left.offset < right.offset : leftPosition < rightPosition
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return left.offset < right.offset
            }
        }.map(\.element)
    }

    public static func groupedApps(
        _ first: [InstalledApp],
        _ second: [InstalledApp],
        orderedBy apps: [InstalledApp]
    ) -> [InstalledApp] {
        let memberPaths = Set((first + second).map(\.path))
        return apps.filter { memberPaths.contains($0.path) }
    }

    public static func groupingUpdate(
        from firstPath: String,
        onto secondPath: String,
        entries: [AppEntry],
        groups: [ManualGroup],
        apps: [InstalledApp],
        context: String?
    ) -> GroupingUpdate? {
        guard firstPath != secondPath,
              let first = entries.first(where: { $0.path == firstPath }),
              let second = entries.first(where: { $0.path == secondPath }) else {
            return nil
        }

        let firstChildren = first.app.map { [$0] } ?? first.children
        let secondChildren = second.app.map { [$0] } ?? second.children
        let incomingPaths = groupedApps(firstChildren, secondChildren, orderedBy: apps).map(\.path)
        guard incomingPaths.count >= 2 else { return nil }

        let incomingMembers = Set(incomingPaths)
        let overlappingGroups = groups.filter { group in
            group.context == context && !Set(group.appPaths).isDisjoint(with: incomingMembers)
        }
        let targetGroupID = secondPath.hasPrefix("manual-folder:")
            ? String(secondPath.dropFirst("manual-folder:".count))
            : nil
        let retainedGroup = overlappingGroups.first { $0.id == targetGroupID }
            ?? overlappingGroups.first
        let groupedPaths = groupedApps(
            overlappingGroups.flatMap { group in
                group.appPaths.compactMap { path in apps.first { $0.path == path } }
            },
            incomingPaths.compactMap { path in apps.first { $0.path == path } },
            orderedBy: apps
        ).map(\.path)

        let group = ManualGroup(
            id: retainedGroup?.id ?? UUID().uuidString,
            name: retainedGroup?.name ?? "文件夹",
            context: context,
            appPaths: groupedPaths
        )
        var updatedGroups = groups.filter { !overlappingGroups.contains($0) }
        updatedGroups.append(group)

        let order = orderAfterGrouping(
            entries,
            memberPaths: Set(groupedPaths),
            groupPath: "manual-folder:\(group.id)"
        )
        return GroupingUpdate(groups: updatedGroups, group: group, order: order)
    }

    public static func orderAfterGrouping(
        _ entries: [AppEntry],
        memberPaths: Set<String>,
        groupPath: String
    ) -> [String] {
        var result: [String] = []
        var insertedGroup = false

        for entry in entries {
            if memberPaths.contains(entry.path) {
                if !insertedGroup {
                    result.append(groupPath)
                    insertedGroup = true
                }
            } else if entry.kind == .folder, !entry.children.isEmpty {
                let groupedChildren = entry.children.filter { memberPaths.contains($0.path) }
                if !groupedChildren.isEmpty {
                    if !insertedGroup {
                        result.append(groupPath)
                        insertedGroup = true
                    }
                    result.append(contentsOf: entry.children
                        .filter { !memberPaths.contains($0.path) }
                        .map(\.path))
                } else {
                    result.append(entry.path)
                }
            } else {
                result.append(entry.path)
            }
        }

        if !insertedGroup {
            result.append(groupPath)
        }
        return result
    }

    public static func reordered(_ paths: [String], moving path: String, to insertionIndex: Int) -> [String] {
        guard let sourceIndex = paths.firstIndex(of: path) else { return paths }
        var result = paths
        result.remove(at: sourceIndex)
        let adjustedIndex = insertionIndex > sourceIndex ? insertionIndex - 1 : insertionIndex
        result.insert(path, at: min(max(adjustedIndex, 0), result.count))
        return result
    }
}

@MainActor
public final class LaunchpadStore: ObservableObject {
    @Published public private(set) var apps: [InstalledApp] = []
    @Published public private(set) var groups: [ManualGroup] = []
    @Published public private(set) var appOrders: [String: [String]] = [:]
    @Published public var errorMessage: String?
    @Published public var draggedPath: String?
    public var dismissAction: (() -> Void)?

    private let fileManager = FileManager.default
    private let supportDirectory: URL
    private let groupsURL: URL
    private let ordersURL: URL
    private var scanTask: Task<Void, Never>?

    public init() {
        let home = fileManager.homeDirectoryForCurrentUser
        supportDirectory = home
            .appendingPathComponent("Library/Application Support/launchpadapp", isDirectory: true)
        groupsURL = supportDirectory.appendingPathComponent("app-groups.json")
        ordersURL = supportDirectory.appendingPathComponent("app-order.json")
        groups = (try? JSONDecoder().decode([ManualGroup].self, from: Data(contentsOf: groupsURL))) ?? []
        appOrders = (try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: ordersURL))) ?? [:]
        refreshApplications()
    }

    deinit {
        scanTask?.cancel()
    }

    public func refreshApplications() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let scanned = try await Task.detached(priority: .userInitiated) {
                    try Self.scanApplications()
                }.value
                guard !Task.isCancelled else { return }
                self.apps = scanned
            } catch {
                self.errorMessage = "无法扫描应用程序：\(error.localizedDescription)"
            }
        }
    }

    public func entries(in context: String?, manualGroupID: String? = nil, query: String = "") -> [AppEntry] {
        let scopedApps: [InstalledApp]
        if let manualGroupID,
           let group = groups.first(where: { $0.id == manualGroupID }) {
            scopedApps = group.appPaths.compactMap { path in apps.first { $0.path == path } }
        } else if let context {
            scopedApps = apps.filter { LaunchpadLogic.parentDirectory(for: $0.path) == context }
        } else {
            scopedApps = apps
        }

        let baseEntries = context == nil && manualGroupID == nil
            ? LaunchpadLogic.folderEntries(from: scopedApps)
            : scopedApps.map(AppEntry.application)

        let entries = manualGroupID == nil
            ? LaunchpadLogic.applyingManualGroups(
                to: baseEntries,
                groups: groups,
                apps: apps,
                context: context
            )
            : baseEntries

        let key = Self.orderKey(for: context)
        let order = manualGroupID == nil ? appOrders[key] ?? [] : []
        return LaunchpadLogic.ordered(LaunchpadLogic.filtered(entries, query: query), paths: order)
    }

    public func children(of entry: AppEntry) -> [InstalledApp] {
        if let groupID = entry.manualGroupID,
           let group = groups.first(where: { $0.id == groupID }) {
            return group.appPaths.compactMap { path in apps.first { $0.path == path } }
        }
        return entry.children
    }

    public func open(_ app: InstalledApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: app.path),
            configuration: configuration
        ) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.errorMessage = "无法打开“\(app.name)”：\(error.localizedDescription)"
            }
        }
    }

    public func icon(for path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    public func saveOrder(_ paths: [String], context: String?) {
        let uniquePaths = Array(NSOrderedSet(array: paths)) as? [String] ?? paths
        appOrders[Self.orderKey(for: context)] = uniquePaths
        do {
            try persist(appOrders, to: ordersURL)
        } catch {
            errorMessage = "保存应用排序失败：\(error.localizedDescription)"
        }
    }

    public func createGroup(with firstPath: String, and secondPath: String, context: String?) {
        guard let update = LaunchpadLogic.groupingUpdate(
            from: firstPath,
            onto: secondPath,
            entries: entries(in: context),
            groups: groups,
            apps: apps,
            context: context
        ) else { return }
        groups = update.groups
        persistGroups()
        saveOrder(update.order, context: context)
    }

    public func renameGroup(_ id: String, to name: String) {
        updateGroup(id) { $0.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)).nilIfEmpty ?? "文件夹" }
    }

    public func removeFromGroup(_ appPath: String, groupID: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let context = groups[index].context
        groups[index].appPaths.removeAll { $0 == appPath }
        if groups[index].appPaths.count < 2 {
            let group = groups.remove(at: index)
            var order = appOrders[Self.orderKey(for: context)] ?? []
            let groupPath = "manual-folder:\(group.id)"
            let index = order.firstIndex(of: groupPath) ?? order.count
            order.removeAll { $0 == groupPath }
            order.insert(contentsOf: group.appPaths, at: min(index, order.count))
            saveOrder(order, context: context)
        }
        persistGroups()
    }

    public func reorder(
        _ paths: [String],
        moving path: String,
        to insertionIndex: Int,
        context: String?,
        manualGroupID: String? = nil
    ) {
        let result = LaunchpadLogic.reordered(paths, moving: path, to: insertionIndex)
        guard result != paths else { return }
        if let manualGroupID {
            updateGroup(manualGroupID) { $0.appPaths = result }
        } else {
            saveOrder(result, context: context)
        }
    }

    public func dismissError() {
        errorMessage = nil
    }

    public func dismiss() {
        dismissAction?()
    }

    private func updateGroup(_ id: String, transform: (inout ManualGroup) -> Void) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        transform(&groups[index])
        persistGroups()
    }

    private func persistGroups() {
        do {
            try persist(groups, to: groupsURL)
        } catch {
            errorMessage = "保存文件夹失败：\(error.localizedDescription)"
        }
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func orderKey(for context: String?) -> String {
        context.map { "folder:\($0)" } ?? "root"
    }

    nonisolated private static func scanApplications() throws -> [InstalledApp] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        var found: [String: InstalledApp] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                let bundle = Bundle(url: url)
                let localizedInfo = bundle?.localizedInfoDictionary ?? [:]
                let info = bundle?.infoDictionary ?? [:]
                let name = localizedInfo["CFBundleDisplayName"] as? String
                    ?? localizedInfo["CFBundleName"] as? String
                    ?? bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                    ?? info["CFBundleDisplayName"] as? String
                    ?? info["CFBundleName"] as? String
                    ?? fileManager.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                found[url.path] = InstalledApp(name: name, path: url.path)
                enumerator.skipDescendants()
            }
        }
        return found.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
