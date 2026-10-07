import SwiftUI
import AppKit
import PerasmaCore

@MainActor enum UICapture {
    static var started = false
    static func runIfRequested() {
        guard !started, let index = CommandLine.arguments.firstIndex(of: "--capture-ui"), CommandLine.arguments.indices.contains(index + 1) else { return }
        started = true
        let destination = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        do { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) } catch { exit(1) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = LibraryStore(root: root)
        store.preferences.onboardingComplete = true
        let environment = WindowsEnvironment(name: "Example environment")
        store.library.environments = [environment]
        store.library.apps = [WindowsApp(name: "Example editor", path: "/Example/editor.exe", category: .programs, environmentID: environment.id), WindowsApp(name: "Example game", path: "/Example/game.exe", category: .games, environmentID: environment.id)]
        store.selectedID = store.library.apps.first?.id
        let library = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        library.title = "Perasma"; library.contentView = NSHostingView(rootView: LibraryView().environmentObject(store)); library.center(); library.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            do { try capture(library, to: destination.appendingPathComponent("library.png")) } catch { print(error); exit(1) }
            library.orderOut(nil)
            let setup = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            setup.title = "Welcome to Perasma"; setup.contentView = NSHostingView(rootView: OnboardingView().environmentObject(store)); setup.center(); setup.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                do { try capture(setup, to: destination.appendingPathComponent("onboarding.png")) } catch { print(error); exit(1) }
                setup.contentView = NSHostingView(rootView: OnboardingView(initialStep: 2).environmentObject(store))
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    do { try capture(setup, to: destination.appendingPathComponent("setup.png")); try? FileManager.default.removeItem(at: root); print("PERASMA_UI_CAPTURE_SUCCEEDED"); exit(0) } catch { print(error); exit(1) }
                }
            }
        }
    }
    private static func capture(_ window: NSWindow, to url: URL) throws {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try capture.run()
        capture.waitUntilExit()
        guard capture.terminationStatus == 0, let image = NSImage(contentsOf: url), image.size.width > 0 else { throw NSError(domain: "Capture", code: 3, userInfo: [NSLocalizedDescriptionKey: "WindowServer screenshot failed. Native GPU surfaces must be verified before release."]) }
    }
}
