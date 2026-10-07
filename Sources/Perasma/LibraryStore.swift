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
    func add(url: URL, name: String, category: AppCategory, environmentID: UUID?) {
        let environment: UUID
        if let environmentID { environment = environmentID }
        else { let item = WindowsEnvironment(name: name); library.environments.append(item); environment = item.id }
        let app = WindowsApp(name: name, path: url.path, category: category, environmentID: environment)
        library.apps.append(app); selectedID = app.id; importURL = nil; save()
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
            let process = Process(); process.executableURL = URL(fileURLWithPath: preferences.runtimePath); process.arguments = LaunchPlan.arguments(for: url)
            process.currentDirectoryURL = url.deletingLastPathComponent()
            var env = ProcessInfo.processInfo.environment; env["WINEPREFIX"] = prefix.path
            let graphics = library.environments.first { $0.id == app.environmentID }?.graphics
            if let overrides = ComponentPolicy.overrides(graphics: graphics) { env["WINEDLLOVERRIDES"] = overrides }
            process.environment = env
            process.standardOutput = handle; process.standardError = handle
            process.terminationHandler = { [weak self] child in
                try? handle.close()
                Task { @MainActor in
                    self?.running.remove(app.id); self?.processes.removeValue(forKey: app.id)
                    if child.terminationStatus != 0 { self?.error = "Wine exited with code \(child.terminationStatus). Open the app log for details. Compatibility is not guaranteed." }
                }
            }
            try process.run(); processes[app.id] = process; running.insert(app.id)
            if let i = library.apps.firstIndex(where: { $0.id == app.id }) { library.apps[i].lastOpened = Date(); save() }
        } catch { self.error = "The app could not start: \(error.localizedDescription)" }
    }
    func chooseIcon(for app: WindowsApp) { let panel = NSOpenPanel(); panel.message = "Choose this app's genuine icon image."; if panel.runModal() == .OK, let url = panel.url, NSImage(contentsOf: url) != nil, let i = library.apps.firstIndex(where: { $0.id == app.id }) { library.apps[i].iconPath = url.path; save() } }
    func remove(_ app: WindowsApp) { library.apps.removeAll { $0.id == app.id }; if selectedID == app.id { selectedID = nil }; save() }
    func revealEnvironment(_ app: WindowsApp) { let url = LaunchPlan.prefix(root: root, id: app.environmentID); do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); NSWorkspace.shared.open(url) } catch { self.error = error.localizedDescription } }
    func revealLog(_ app: WindowsApp) { let url = root.appendingPathComponent("Logs/\(app.id.uuidString).log"); if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) } else { error = "No log is available yet. Launch this app first." } }
}
