import SwiftUI
import AppKit
import PerasmaCore

struct ImportView: View {
    @EnvironmentObject var store: LibraryStore
    let url: URL
    @State private var name = ""
    @State private var category: AppCategory = .programs
    @State private var environmentID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Add Windows app").font(.title.bold())
            Text("This adds a library entry. It does not run or install the file yet.").foregroundStyle(.secondary)
            Text(url.lastPathComponent).font(.caption).textSelection(.enabled)
            Form {
                TextField("Name", text: $name)
                Picker("Category", selection: $category) { ForEach(AppCategory.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Environment", selection: $environmentID) {
                    Text("New environment").tag(Optional<UUID>.none)
                    ForEach(store.library.environments) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Text("Use an existing environment for an installer or program belonging to an app you already added. Environments separate Windows settings, not security permissions.").font(.callout).foregroundStyle(.secondary)
            HStack { Button("Cancel") { store.importURL = nil }; Spacer(); Button("Add app") { store.add(url: url, name: name.trimmingCharacters(in: .whitespacesAndNewlines), category: category, environmentID: environmentID) }.buttonStyle(.glassProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(32).frame(width: 520).onAppear { name = url.deletingPathExtension().lastPathComponent }
    }
}
struct PreferencesControls: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        Picker("Default library view", selection: $store.preferences.layout) { ForEach(LibraryLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
        Toggle("Show app details", isOn: $store.preferences.showInspector)
        Toggle("Ask before running Windows software", isOn: $store.preferences.confirmLaunch)
    }
}
struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @StateObject private var setup = RuntimeSetup()
    var body: some View {
        Form {
            Section("Library and safety") { PreferencesControls() }
            Section("Download and setup") { RuntimeSetupView(setup: setup) }
            Section("Finder") { Text("Use Finder's Open With menu to select Perasma for .exe and .msi files. Change the default in Get Info only if you want to. Perasma never silently changes your associations.").font(.callout) }
            Section("Onboarding") { Button("Show onboarding again") { store.preferences.onboardingComplete = false; store.save() } }
        }.formStyle(.grouped).padding().frame(width: 760, height: 730).onChange(of: store.preferences) { _, _ in store.save() }
    }
}
struct OnboardingView: View {
    @EnvironmentObject var store: LibraryStore
    @StateObject private var setup: RuntimeSetup
    @State private var step: Int
    private let showIntegrations: Bool
    @MainActor init(initialStep: Int = 0, runtimeSetup: RuntimeSetup? = nil, showIntegrations: Bool = false) { self.showIntegrations = showIntegrations; _step = State(initialValue: initialStep); _setup = StateObject(wrappedValue: runtimeSetup ?? RuntimeSetup()) }
    private let titles = ["Windows software. At home on Mac.", "Local by default. Honest about limits.", "Make Perasma yours.", "Set up Windows components."]
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack { Text("Perasma").font(.headline); Spacer(); Text("\(step + 1) of 4").font(.caption).foregroundStyle(.secondary) }
            Image(systemName: step == 0 ? "macwindow" : step == 1 ? "lock.shield" : step == 2 ? "slider.horizontal.3" : "arrow.down.circle").font(.system(size: 44, weight: .light)).foregroundStyle(.tint).accessibilityHidden(true)
            Text(titles[step]).font(.system(size: 31, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Group {
                if step == 0 {
                    Text("Keep Windows programs and games in one native library. Open .exe files from Finder, keep environments organized, and start apps without Terminal.")
                    Text("A compatible Wine runtime is required. Download it from its publisher during setup. Not every Windows app will work.").foregroundStyle(.secondary)
                } else if step == 1 {
                    Text("Your library, preferences and launch logs stay in Application Support on this Mac. Perasma has no analytics or cloud library.")
                    Text("Windows apps themselves can connect to the internet and access files available to your Mac account. Wine environments are not security sandboxes. Only run software you trust.").foregroundStyle(.secondary)
                } else if step == 2 {
                    PreferencesControls()
                    Text("Every choice here can be changed later in Settings.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView { RuntimeSetupView(setup: setup) }
                            .onAppear { if showIntegrations { proxy.scrollTo("integrations", anchor: .top) } }
                    }
                }
            }.font(.body).lineSpacing(4)
            Spacer(minLength: 0)
            HStack { if step > 0 { Button("Back") { withAnimation { step -= 1 } } }; Spacer(); Button(step == 3 ? (store.runtimeAvailable ? "Open library" : "Set up later") : "Continue") { if step == 3 { store.preferences.onboardingComplete = true; store.save() } else { withAnimation { step += 1 } } }.buttonStyle(.glassProminent).disabled(step == 3 && (setup.busy || setup.mediaBusy)) }
        }.padding(40).frame(width: 720, height: 700)
    }
}
