import SwiftUI
import AppKit
import PerasmaCore

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var store: LibraryStore?
    private var pending: [URL] = []
    func application(_ application: NSApplication, open urls: [URL]) { for url in urls { if let store { store.receive(url) } else { pending.append(url) } } }
    func connect(_ store: LibraryStore) { self.store = store; let urls = pending; pending.removeAll(); urls.forEach(store.receive) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct PerasmaApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) var delegate
    @StateObject private var store = LibraryStore()
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(store).frame(minWidth: 950, minHeight: 620)
                .onAppear { delegate.connect(store); UICapture.runIfRequested() }
                .alert("Perasma", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
                .alert("Run this Windows app?", isPresented: Binding(get: { store.pendingLaunch != nil }, set: { if !$0 { store.pendingLaunch = nil } })) {
                    Button("Cancel", role: .cancel) { store.pendingLaunch = nil }
                    Button("Run") { if let app = store.pendingLaunch { store.launch(app) } }
                } message: { Text("Only run software you trust. Wine environments keep app settings separate, but are not security sandboxes. Windows software may access files allowed by your Mac account.") }
                .sheet(isPresented: Binding(get: { !store.preferences.onboardingComplete }, set: { _ in })) { OnboardingView().environmentObject(store).interactiveDismissDisabled() }
                .sheet(isPresented: Binding(get: { store.importURL != nil && store.preferences.onboardingComplete }, set: { if !$0 { store.importURL = nil } })) { if let url = store.importURL { ImportView(url: url).environmentObject(store) } }
        }
        .commands { CommandGroup(after: .newItem) { Button("Open Windows app...") { store.chooseFile() }.keyboardShortcut("o") } }
        Settings { SettingsView().environmentObject(store) }
    }
}
