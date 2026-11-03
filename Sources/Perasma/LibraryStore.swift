import SwiftUI
import AppKit
import PerasmaCore

@MainActor final class LibraryStore: ObservableObject {
    @Published var library = Library()
    @Published var preferences = Preferences()
    @Published var selectedID: UUID?
    @Published var error: String?
    @Published var running: Set<UUID> = []
    @Published var importURL: URL?
    @Published var pendingLaunch: WindowsApp?
    private var storageReadable = true
    private var processes: [UUID: Process] = [:]
    let root: URL
    private let libraryURL: URL
    private let preferencesURL: URL
    init(root: URL? = nil) {
        let support = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Perasma", isDirectory: true)
        self.root = support; libraryURL = support.appendingPathComponent("Library.json"); preferencesURL = support.appendingPathComponent("Preferences.json")
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: libraryURL.path) { library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: libraryURL)) }
            if FileManager.default.fileExists(atPath: preferencesURL.path) { preferences = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: preferencesURL)) }
        } catch { storageReadable = false; self.error = "Your saved library could not be read. No files were replaced. \(error.localizedDescription)" }
    }
    var selected: WindowsApp? { library.apps.first { $0.id == selectedID } }
    var runtimeAvailable: Bool { !preferences.runtimePath.isEmpty && FileManager.default.isExecutableFile(atPath: preferences.runtimePath) }
    func save() {
        guard storageReadable else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(library).write(to: libraryURL, options: .atomic); try encoder.encode(preferences).write(to: preferencesURL, options: .atomic) }
        catch { self.error = "Changes could not be saved: \(error.localizedDescription)" }
    }
    func receive(_ url: URL) {
        guard LaunchPlan.accepts(url) else { error = "Choose a Windows .exe or .msi file."; return }
        guard FileManager.default.fileExists(atPath: url.path) else { error = "This file is no longer available."; return }
        if let existing = library.apps.first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL == url.standardizedFileURL }) { selectedID = existing.id; requestLaunch(existing) }
        else { importURL = url }
    }
    func chooseFile() { let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false; panel.message = "Choose a Windows executable or installer."; if panel.runModal() == .OK, let url = panel.url { receive(url) } }
    @discardableResult func add(url: URL, name: String, category: AppCategory, environmentID: UUID?) -> WindowsApp {
        if let existing = library.apps.first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL == url.standardizedFileURL }) {
            selectedID = existing.id; importURL = nil; return existing
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? url.deletingPathExtension().lastPathComponent : trimmed
        let environment: UUID
        if let environmentID, library.environment(id: environmentID) != nil { environment = environmentID }
        else { let item = WindowsEnvironment(name: displayName); library.environments.append(item); environment = item.id }
        let app = WindowsApp(name: displayName, path: url.path, category: category, environmentID: environment)
        library.apps.append(app); selectedID = app.id; importURL = nil; save()
        return app
    }
    func update(_ app: WindowsApp) {
        guard let i = library.apps.firstIndex(where: { $0.id == app.id }) else { return }
        var edited = app
        let trimmed = edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { edited.name = library.apps[i].name } else { edited.name = trimmed }
        if library.environment(id: edited.environmentID) == nil { edited.environmentID = library.apps[i].environmentID }
        library.apps[i] = edited; save()
    }
    func toggleFavorite(_ app: WindowsApp) {
        guard let i = library.apps.firstIndex(where: { $0.id == app.id }) else { return }
        library.apps[i].favorite.toggle(); save()
    }
    func requestLaunch(_ app: WindowsApp) {
        guard runtimeAvailable else { error = "The Wine runtime is not set up yet. Download it under Download and setup in Settings. No runtime is bundled in this build."; return }
        if preferences.confirmLaunch { pendingLaunch = app } else { launch(app) }
    }
    func launch(_ app: WindowsApp) {
        pendingLaunch = nil
        guard !running.contains(app.id), runtimeAvailable else { return }
        let url = URL(fileURLWithPath: app.path)
        guard FileManager.default.fileExists(atPath: url.path) else { error = "The app file has moved or is missing. Re-add its current location."; return }
        let prefix = LaunchPlan.prefix(root: root, id: app.environmentID)
        do {
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
            let logs = root.appendingPathComponent("Logs", isDirectory: true)
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let logURL = logs.appendingPathComponent("\(app.id.uuidString).log")
            if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: logURL); try handle.truncate(atOffset: 0)
            let process = Process(); process.executableURL = URL(fileURLWithPath: preferences.runtimePath); process.arguments = LaunchPlan.arguments(for: url, customArguments: app.launchArguments)
            process.currentDirectoryURL = url.deletingLastPathComponent()
            var env = ProcessInfo.processInfo.environment
            for (key, value) in LaunchPlan.environmentVariables(prefix: prefix, graphics: library.environment(for: app)?.graphics) { env[key] = value }
            process.environment = env
            process.standardOutput = handle; process.standardError = handle
            process.terminationHandler = { [weak self] child in
                try? handle.close()
                Task { @MainActor in
                    guard let self, self.processes[app.id] === child else { return }
                    self.running.remove(app.id); self.processes.removeValue(forKey: app.id)
                    if child.terminationStatus != 0 { self.error = "Wine exited with code \(child.terminationStatus). Open the app log for details. Compatibility is not guaranteed." }
                }
            }
            try process.run(); processes[app.id] = process; running.insert(app.id)
            if let i = library.apps.firstIndex(where: { $0.id == app.id }) { library.apps[i].lastOpened = Date(); save() }
        } catch { self.error = "The app could not start: \(error.localizedDescription)" }
    }
    func stop(_ app: WindowsApp) {
        guard let process = processes[app.id] else { return }
        process.terminate()
        running.remove(app.id); processes.removeValue(forKey: app.id)
    }
    func isRunning(_ app: WindowsApp) -> Bool { running.contains(app.id) }
    func chooseIcon(for app: WindowsApp) { let panel = NSOpenPanel(); panel.message = "Choose this app's genuine icon image."; if panel.runModal() == .OK, let url = panel.url, NSImage(contentsOf: url) != nil, let i = library.apps.firstIndex(where: { $0.id == app.id }) { library.apps[i].iconPath = url.path; save() } }
    func removeIcon(for app: WindowsApp) { if let i = library.apps.firstIndex(where: { $0.id == app.id }) { library.apps[i].iconPath = nil; save() } }
    func remove(_ app: WindowsApp) { stop(app); library.apps.removeAll { $0.id == app.id }; if selectedID == app.id { selectedID = nil }; save() }
    // MARK: environments
    @discardableResult func createEnvironment(name: String, graphics: GraphicsBackend? = nil) -> WindowsEnvironment {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = WindowsEnvironment(name: trimmed.isEmpty ? "New environment" : trimmed, graphics: graphics)
        library.environments.append(item); save(); return item
    }
    func renameEnvironment(_ environment: WindowsEnvironment, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = library.environments.firstIndex(where: { $0.id == environment.id }) else { return }
        library.environments[i].name = trimmed; save()
    }
    func setGraphics(_ graphics: GraphicsBackend?, for environment: WindowsEnvironment) {
        guard let i = library.environments.firstIndex(where: { $0.id == environment.id }) else { return }
        library.environments[i].graphics = graphics; save()
    }
    // apps in a deleted environment move to the first remaining one (created on demand), so nothing is orphaned
    func deleteEnvironment(_ environment: WindowsEnvironment) {
        guard library.environments.contains(where: { $0.id == environment.id }) else { return }
        library.environments.removeAll { $0.id == environment.id }
        if library.apps.contains(where: { $0.environmentID == environment.id }) {
            let fallback = library.environments.first ?? createEnvironment(name: "Default")
            for i in library.apps.indices where library.apps[i].environmentID == environment.id { library.apps[i].environmentID = fallback.id }
        }
        save()
    }
    func deleteEnvironmentFiles(_ environment: WindowsEnvironment) {
        for app in library.apps(in: environment.id) { stop(app) }
        let url = LaunchPlan.prefix(root: root, id: environment.id)
        do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } }
        catch { self.error = "The environment files could not be moved to Trash: \(error.localizedDescription)" }
    }
    func revealEnvironment(_ environment: WindowsEnvironment) { let url = LaunchPlan.prefix(root: root, id: environment.id); do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); NSWorkspace.shared.open(url) } catch { self.error = error.localizedDescription } }
    func revealEnvironment(_ app: WindowsApp) { if let environment = library.environment(for: app) { revealEnvironment(environment) } else { error = "This app's environment is missing." } }
    // MARK: runtime + files
    func chooseRuntime() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false; panel.message = "Choose an existing Wine executable (usually named wine or wine64)."
        if panel.runModal() == .OK, let url = panel.url {
            guard FileManager.default.isExecutableFile(atPath: url.path) else { error = "That file is not executable, so it cannot be used as the Wine runtime."; return }
            preferences.runtimePath = url.path; save()
        }
    }
    func clearRuntime() { preferences.runtimePath = ""; save() }
    func revealAppInFinder(_ app: WindowsApp) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)]) }
    func revealLog(_ app: WindowsApp) { let url = root.appendingPathComponent("Logs/\(app.id.uuidString).log"); if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) } else { error = "No log is available yet. Launch this app first." } }
    func logPreview(for app: WindowsApp, maxLines: Int = 40) -> String? {
        let url = root.appendingPathComponent("Logs/\(app.id.uuidString).log")
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(maxLines).joined(separator: "\n")
    }
}
