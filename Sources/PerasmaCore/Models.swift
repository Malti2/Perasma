import Foundation
public enum AppCategory: String, Codable, CaseIterable, Identifiable { case games = "Games", programs = "Programs"; public var id: String { rawValue } }
public struct WindowsApp: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var path: String
    public var category: AppCategory
    public var environmentID: UUID
    public var iconPath: String?
    public var lastOpened: Date?
    public init(id: UUID = UUID(), name: String, path: String, category: AppCategory, environmentID: UUID, iconPath: String? = nil) { self.id = id; self.name = name; self.path = path; self.category = category; self.environmentID = environmentID; self.iconPath = iconPath }
}
public struct WindowsEnvironment: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var graphics: GraphicsBackend?
    public init(id: UUID = UUID(), name: String, graphics: GraphicsBackend? = nil) { self.id = id; self.name = name; self.graphics = graphics }
}
public enum LibraryLayout: String, Codable, CaseIterable { case grid = "Grid", list = "List" }
public struct Preferences: Codable, Equatable {
    public var runtimePath = ""
    public var layout: LibraryLayout = .grid
    public var confirmLaunch = true
    public var showInspector = true
    public var onboardingComplete = false
    public init() {}
}
public struct Library: Codable {
    public var apps: [WindowsApp] = []
    public var environments: [WindowsEnvironment] = []
    public init() {}
}
public enum LaunchPlan {
    public static func arguments(for url: URL) -> [String] { url.pathExtension.lowercased() == "msi" ? ["msiexec", "/i", url.path] : [url.path] }
    public static func accepts(_ url: URL) -> Bool { ["exe", "msi"].contains(url.pathExtension.lowercased()) }
    public static func prefix(root: URL, id: UUID) -> URL { root.appendingPathComponent("Environments", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true) }
}

public enum GraphicsBackend: String, Codable { case dxvk }
public enum ComponentPolicy {
    public static let graphicsDLLs = ["d3d10core.dll", "d3d11.dll"]
    public static func safeArchiveEntry(_ entry: String, root: String) -> Bool {
        guard entry.hasPrefix(root + "/"), !entry.hasPrefix("/") else { return false }
        return !entry.split(separator: "/").contains("..")
    }
    public static func overrides(graphics: GraphicsBackend?) -> String? {
        graphics == .dxvk ? "d3d10core,d3d11=n,b" : nil
    }
}
