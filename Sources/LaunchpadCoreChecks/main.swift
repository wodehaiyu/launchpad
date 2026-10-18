import Foundation
import LaunchpadCore

@main
enum LaunchpadLogicChecks {
    static let apps = [
        InstalledApp(name: "Chrome", path: "/Applications/Chrome.app"),
        InstalledApp(name: "Notes", path: "/Applications/Notes.app"),
        InstalledApp(name: "One", path: "/Applications/Tools/One.app"),
        InstalledApp(name: "Two", path: "/Applications/Tools/Two.app"),
        InstalledApp(name: "Terminal", path: "/System/Applications/Utilities/Terminal.app"),
        InstalledApp(name: "Activity Monitor", path: "/System/Applications/Utilities/Activity Monitor.app")
    ]

    static func main() {
        checkAutomaticFolders()
        checkManualGroups()
        checkGroupingAutomaticFolder()
        checkGroupingPartOfAutomaticFolder()
        checkGroupingApps()
        checkGroupingUpdateAndPersistence()
        checkExtendingManualGroup()
        checkNestedGroupingUpdate()
        checkGroupOrderPreservation()
        checkReordering()
        checkLegacyGroupPersistence()
        checkNestedManualGroups()
        checkSearchAndOrder()
        print("All native logic checks passed.")
    }

    private static func checkAutomaticFolders() {
        let entries = LaunchpadLogic.folderEntries(from: apps)
        precondition(entries.contains { $0.name == "Chrome" && $0.kind == .application })
        precondition(entries.contains { $0.name == "Tools" && $0.children.map(\.name) == ["One", "Two"] })
        precondition(entries.contains { $0.name == "Utilities" })
    }

    private static func checkManualGroups() {
        let group = ManualGroup(
            id: "group-1",
            name: "常用",
            context: nil,
            appPaths: [apps[0].path, apps[1].path]
        )
        let entries = LaunchpadLogic.applyingManualGroups(
            to: LaunchpadLogic.folderEntries(from: apps),
            groups: [group],
            apps: apps,
            context: nil
        )
        precondition(!entries.contains { $0.path == apps[0].path })
        precondition(entries.contains { $0.path == "manual-folder:group-1" && $0.name == "常用" })
        precondition(entries.first { $0.path == "manual-folder:group-1" }?.children.map(\.path) == group.appPaths)
    }

    private static func checkGroupingAutomaticFolder() {
        let group = ManualGroup(
            id: "mixed-group",
            name: "混合分组",
            context: nil,
            appPaths: [apps[0].path, apps[2].path, apps[3].path]
        )
        let entries = LaunchpadLogic.applyingManualGroups(
            to: LaunchpadLogic.folderEntries(from: apps),
            groups: [group],
            apps: apps,
            context: nil
        )
        precondition(entries.contains { $0.path == "manual-folder:mixed-group" })
        precondition(!entries.contains { $0.path == apps[0].path || $0.path == "/Applications/Tools" })
    }

    private static func checkGroupingPartOfAutomaticFolder() {
        let group = ManualGroup(
            id: "partial-group",
            name: "部分分组",
            context: nil,
            appPaths: [apps[0].path, apps[2].path]
        )
        let entries = LaunchpadLogic.applyingManualGroups(
            to: LaunchpadLogic.folderEntries(from: apps),
            groups: [group],
            apps: apps,
            context: nil
        )
        let groupedEntry = entries.first { $0.path == "manual-folder:partial-group" }
        precondition(groupedEntry?.children.map(\.path) == group.appPaths)
        precondition(entries.contains { $0.path == apps[3].path && $0.kind == .application })
        precondition(!entries.contains { $0.path == "/Applications/Tools" })
    }

    private static func checkGroupingApps() {
        let grouped = LaunchpadLogic.groupedApps(
            [apps[1], apps[0]],
            [apps[0], apps[2]],
            orderedBy: apps
        )
        precondition(grouped == [apps[0], apps[1], apps[2]])
    }

    private static func checkGroupingUpdateAndPersistence() {
        let entries = LaunchpadLogic.folderEntries(from: apps)
        let update = LaunchpadLogic.groupingUpdate(
            from: apps[0].path,
            onto: "/Applications/Tools",
            entries: entries,
            groups: [],
            apps: apps,
            context: nil
        )
        guard let update else { preconditionFailure("Dropping an app onto an automatic folder must create a group.") }

        let groupPath = "manual-folder:\(update.group.id)"
        precondition(update.group.appPaths == [apps[0].path, apps[2].path, apps[3].path])
        precondition(update.order.first == groupPath)
        precondition(update.order.contains(apps[1].path))

        let displayedEntries = LaunchpadLogic.applyingManualGroups(
            to: entries,
            groups: update.groups,
            apps: apps,
            context: nil
        )
        let displayedGroup = displayedEntries.first { $0.path == groupPath }
        precondition(displayedGroup?.children.map(\.path) == update.group.appPaths)
        precondition(!displayedEntries.contains { $0.path == apps[0].path || $0.path == "/Applications/Tools" })

        let encoded = try! JSONEncoder().encode(update.groups)
        let restored = try! JSONDecoder().decode([ManualGroup].self, from: encoded)
        precondition(restored == update.groups)
        precondition(LaunchpadLogic.groupingUpdate(
            from: "/Applications/missing.app",
            onto: "/Applications/Tools",
            entries: entries,
            groups: [],
            apps: apps,
            context: nil
        ) == nil)
    }

    private static func checkExtendingManualGroup() {
        let extraApp = InstalledApp(name: "Calendar", path: "/Applications/Calendar.app")
        let testApps = apps + [extraApp]
        let existing = ManualGroup(
            id: "existing-group",
            name: "常用",
            context: nil,
            appPaths: [apps[0].path, apps[1].path]
        )
        let entries = LaunchpadLogic.applyingManualGroups(
            to: LaunchpadLogic.folderEntries(from: testApps),
            groups: [existing],
            apps: testApps,
            context: nil
        )
        let update = LaunchpadLogic.groupingUpdate(
            from: extraApp.path,
            onto: "manual-folder:\(existing.id)",
            entries: entries,
            groups: [existing],
            apps: testApps,
            context: nil
        )
        guard let update else { preconditionFailure("Dropping an app onto a manual group must extend it.") }
        precondition(update.group.id == existing.id)
        precondition(update.group.name == existing.name)
        precondition(update.group.appPaths == [apps[0].path, apps[1].path, extraApp.path])
        precondition(update.groups == [update.group])
        precondition(update.order.first == "manual-folder:\(existing.id)")
    }

    private static func checkNestedGroupingUpdate() {
        let context = "/Applications/Tools"
        let scopedApps = apps.filter { LaunchpadLogic.parentDirectory(for: $0.path) == context }
        let entries = scopedApps.map(AppEntry.application)
        let update = LaunchpadLogic.groupingUpdate(
            from: scopedApps[0].path,
            onto: scopedApps[1].path,
            entries: entries,
            groups: [],
            apps: apps,
            context: context
        )
        guard let update else { preconditionFailure("Grouping inside an automatic folder must succeed.") }
        precondition(update.group.context == context)
        precondition(update.group.appPaths == scopedApps.map(\.path))
        precondition(update.order == ["manual-folder:\(update.group.id)"])

        let displayedEntries = LaunchpadLogic.applyingManualGroups(
            to: entries,
            groups: update.groups,
            apps: apps,
            context: context
        )
        precondition(displayedEntries.count == 1)
        precondition(displayedEntries.first?.path == "manual-folder:\(update.group.id)")
    }

    private static func checkGroupOrderPreservation() {
        let entries = [
            AppEntry.application(apps[0]),
            AppEntry.application(apps[1]),
            AppEntry.application(apps[2])
        ]
        let order = LaunchpadLogic.orderAfterGrouping(
            entries,
            memberPaths: [apps[1].path, apps[2].path],
            groupPath: "manual-folder:ordered"
        )
        precondition(order == [apps[0].path, "manual-folder:ordered"])

        let automaticFolder = AppEntry.folder(
            name: "Utilities",
            path: "/System/Applications/Utilities",
            children: [apps[4], apps[5]]
        )
        let folderOrder = LaunchpadLogic.orderAfterGrouping(
            [entries[0], automaticFolder, entries[1]],
            memberPaths: [apps[4].path, apps[5].path],
            groupPath: "manual-folder:utilities"
        )
        precondition(folderOrder == [apps[0].path, "manual-folder:utilities", apps[1].path])

        let partialFolderOrder = LaunchpadLogic.orderAfterGrouping(
            [entries[0], automaticFolder, entries[1]],
            memberPaths: [apps[0].path, apps[4].path],
            groupPath: "manual-folder:partial"
        )
        precondition(partialFolderOrder == ["manual-folder:partial", apps[5].path, apps[1].path])
    }

    private static func checkReordering() {
        let paths = ["a", "b", "c", "d"]
        precondition(LaunchpadLogic.reordered(paths, moving: "a", to: 2) == ["b", "a", "c", "d"])
        precondition(LaunchpadLogic.reordered(paths, moving: "d", to: 1) == ["a", "d", "b", "c"])
        precondition(LaunchpadLogic.reordered(paths, moving: "b", to: 2) == paths)
        precondition(LaunchpadLogic.reordered(paths, moving: "missing", to: 2) == paths)
    }

    private static func checkSearchAndOrder() {
        let entries = LaunchpadLogic.folderEntries(from: apps)
        precondition(LaunchpadLogic.filtered(entries, query: "two").map(\.name) == ["Tools"])
        let sorted = LaunchpadLogic.ordered(entries, paths: [apps[0].path])
        precondition(sorted.first?.path == apps[0].path)
    }

    private static func checkNestedManualGroups() {
        let context = "/System/Applications/Utilities"
        let children = apps.filter { LaunchpadLogic.parentDirectory(for: $0.path) == context }
        let group = ManualGroup(
            id: "nested-group",
            name: "常用工具",
            context: context,
            appPaths: children.map(\.path)
        )
        let entries = LaunchpadLogic.applyingManualGroups(
            to: children.map(AppEntry.application),
            groups: [group],
            apps: apps,
            context: context
        )
        precondition(entries.count == 1)
        precondition(entries.first?.path == "manual-folder:nested-group")
    }

    private static func checkLegacyGroupPersistence() {
        let legacyJSON = """
        [{"id":"legacy","name":"常用","context":null,"appPaths":["/Applications/Chrome.app","/Applications/Notes.app"]}]
        """
        let decoder = JSONDecoder()
        let groups = try! decoder.decode([ManualGroup].self, from: Data(legacyJSON.utf8))
        precondition(groups.first?.context == nil)

        let encoded = try! JSONEncoder().encode(groups)
        let object = try! JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
        precondition(object.first?["context"] is NSNull)
    }
}
