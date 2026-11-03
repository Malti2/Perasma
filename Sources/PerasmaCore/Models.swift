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
    public var favorite: Bool
    public var launchArguments: String
    public init(id: UUID = UUID(), name: String, path: String, category: AppCategory, environmentID: UUID, iconPath: String? = nil, lastOpened: Date? = nil, favorite: Bool = false, launchArguments: String = "") {
        self.id = id; self.name = name; self.path = path; self.category = category; self.environmentID = environmentID; self.iconPath = iconPath; self.lastOpened = lastOpened; self.favorite = favorite; self.launchArguments = launchArguments
    }
    private enum CodingKeys: String, CodingKey { case id, name, path, category, environmentID, iconPath, lastOpened, favorite, launchArguments }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        category = try container.decode(AppCategory.self, forKey: .category)
        environmentID = try container.decode(UUID.self, forKey: .environmentID)
        iconPath = try container.decodeIfPresent(String.self, forKey: .iconPath)
        lastOpened = try container.decodeIfPresent(Date.self, forKey: .lastOpened)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        launchArguments = try container.decodeIfPresent(String.self, forKey: .launchArguments) ?? ""
    }
    public var fileName: String { URL(fileURLWithPath: path).lastPathComponent }
    public var customArguments: [String] { LaunchArguments.parse(launchArguments) }
}

public struct WindowsEnvironment: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var graphics: GraphicsBackend?
    public init(id: UUID = UUID(), name: String, graphics: GraphicsBackend? = nil) { self.id = id; self.name = name; self.graphics = graphics }
}

public enum LibraryLayout: String, Codable, CaseIterable { case grid = "Grid", list = "List" }

public enum LibrarySort: String, Codable, CaseIterable, Identifiable { case name = "Name", recentlyOpened = "Recently opened", category = "Category"; public var id: String { rawValue } }

public enum LibrarySection: String, Codable, CaseIterable, Identifiable {
    case all = "All apps", games = "Games", programs = "Programs", favorites = "Favorites", recent = "Recently opened"
    public var id: String { rawValue }
    public func includes(_ app: WindowsApp) -> Bool {
        switch self {
        case .all: return true
        case .games: return app.category == .games
        case .programs: return app.category == .programs
        case .favorites: return app.favorite
        case .recent: return app.lastOpened != nil
        }
    }
}

public struct Preferences: Codable, Equatable {
    public var runtimePath = ""
    public var layout: LibraryLayout = .grid
    public var confirmLaunch = true
    public var showInspector = true
    public var onboardingComplete = false
    public var sort: LibrarySort = .name
    public init() {}
    private enum CodingKeys: String, CodingKey { case runtimePath, layout, confirmLaunch, showInspector, onboardingComplete, sort }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runtimePath = try container.decodeIfPresent(String.self, forKey: .runtimePath) ?? ""
        layout = try container.decodeIfPresent(LibraryLayout.self, forKey: .layout) ?? .grid
        confirmLaunch = try container.decodeIfPresent(Bool.self, forKey: .confirmLaunch) ?? true
        showInspector = try container.decodeIfPresent(Bool.self, forKey: .showInspector) ?? true
        onboardingComplete = try container.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        sort = try container.decodeIfPresent(LibrarySort.self, forKey: .sort) ?? .name
    }
}

public struct Library: Codable {
    public var apps: [WindowsApp] = []
    public var environments: [WindowsEnvironment] = []
    public init() {}
    public func environment(for app: WindowsApp) -> WindowsEnvironment? { environments.first { $0.id == app.environmentID } }
    public func environment(id: UUID) -> WindowsEnvironment? { environments.first { $0.id == id } }
    public func apps(in environmentID: UUID) -> [WindowsApp] { apps.filter { $0.environmentID == environmentID } }
    public func containsApp(atPath path: String) -> Bool {
        let target = URL(fileURLWithPath: path).standardizedFileURL
        return apps.contains { URL(fileURLWithPath: $0.path).standardizedFileURL == target }
    }
    // filtering + sorting in one place so view and tests agree
    public func filteredApps(section: LibrarySection, search: String = "", sort: LibrarySort = .name) -> [WindowsApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = apps.filter { app in
            guard section.includes(app) else { return false }
            guard !query.isEmpty else { return true }
            return app.name.localizedCaseInsensitiveContains(query) || app.fileName.localizedCaseInsensitiveContains(query) || app.category.rawValue.localizedCaseInsensitiveContains(query)
        }
        if section == .recent {
            return matching.sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
        }
        switch sort {
        case .name: return matching.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recentlyOpened: return matching.sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
        case .category: return matching.sorted { a, b in a.category.rawValue == b.category.rawValue ? a.name.localizedStandardCompare(b.name) == .orderedAscending : a.category.rawValue < b.category.rawValue }
        }
    }
}

public enum LaunchArguments {
    // splits a user-typed argument string; quotes group words, backslash escapes the next char inside double quotes
    public static func parse(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false
        var iterator = raw.makeIterator()
        var pending: Character? = iterator.next()
        while let character = pending {
            pending = iterator.next()
            if let active = quote {
                if character == "\\", active == "\"", let next = pending, next == "\"" || next == "\\" {
                    current.append(next); pending = iterator.next()
                } else if character == active {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character; hasToken = true
            } else if character == " " || character == "\t" || character == "\n" {
                if hasToken || !current.isEmpty { result.append(current); current = ""; hasToken = false }
            } else {
                current.append(character); hasToken = true
            }
        }
        if hasToken || !current.isEmpty { result.append(current) }
        return result
    }
}

public enum LaunchPlan {
    public static func arguments(for url: URL) -> [String] { url.pathExtension.lowercased() == "msi" ? ["msiexec", "/i", url.path] : [url.path] }
    public static func arguments(for url: URL, customArguments: String) -> [String] { arguments(for: url) + LaunchArguments.parse(customArguments) }
    public static func accepts(_ url: URL) -> Bool { ["exe", "msi"].contains(url.pathExtension.lowercased()) }
    public static func prefix(root: URL, id: UUID) -> URL { root.appendingPathComponent("Environments", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true) }
    public static func environmentVariables(prefix: URL, graphics: GraphicsBackend?) -> [String: String] {
        var variables = ["WINEPREFIX": prefix.path]
        if let overrides = ComponentPolicy.overrides(graphics: graphics) { variables["WINEDLLOVERRIDES"] = overrides }
        return variables
    }
}

public enum GraphicsBackend: String, Codable, CaseIterable, Identifiable {
    case dxvk
    public var id: String { rawValue }
    public var label: String { "DXVK (D3D10/11)" }
}

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
