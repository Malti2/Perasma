import SwiftUI
import AppKit
import PerasmaCore

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var section: LibrarySection? = .all
    private var currentSection: LibrarySection { section ?? .all }
    @State private var search = ""
    @State private var editingApp: WindowsApp?
    @State private var logPreview: String?
    private var apps: [WindowsApp] { store.library.filteredApps(section: currentSection, search: search, sort: store.preferences.sort) }
    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("Library") { ForEach(LibrarySection.allCases) { value in Label(value.rawValue, systemImage: symbol(for: value)).tag(value) } }
                if !store.library.environments.isEmpty {
                    Section("Environments") { ForEach(store.library.environments) { environment in HStack { Text(environment.name).lineLimit(1); Spacer(); Text("\(store.library.apps(in: environment.id).count)").font(.caption).foregroundStyle(.secondary) } } }
                }
            }.navigationSplitViewColumnWidth(min: 170, ideal: 205, max: 250)
        } detail: {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) { Text(currentSection.rawValue).font(.largeTitle.bold()); Text("Your Windows apps, in one place.").foregroundStyle(.secondary) }
                    Spacer()
                    Picker("Sort", selection: $store.preferences.sort) { ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 170)
                    Picker("Layout", selection: $store.preferences.layout) { ForEach(LibraryLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().pickerStyle(.segmented).frame(width: 130)
                }
                if !store.runtimeAvailable {
                    HStack(spacing: 12) { Image(systemName: "info.circle"); Text("Set up Windows components in Settings before running apps.").font(.callout); Spacer(); SettingsLink { Text("Settings") } }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
                if apps.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        if store.preferences.layout == .grid {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 225), spacing: 16)], spacing: 16) { ForEach(apps) { app in appCard(app) } }
                        } else { LazyVStack(spacing: 0) { ForEach(apps) { app in appRow(app); Divider() } } }
                    }
                }
                Spacer(minLength: 0)
                Text("Drop an .exe or .msi to add a Windows app.").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(18).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
            }.padding(28).navigationTitle("Perasma")
                .searchable(text: $search, prompt: "Search library")
                .toolbar {
                    ToolbarItem { Button { store.chooseFile() } label: { Label("Add app", systemImage: "plus") } }
                    ToolbarItem { Button { store.preferences.showInspector.toggle(); store.save() } label: { Label("App details", systemImage: "sidebar.right") } }
                }
                .dropDestination(for: URL.self) { urls, _ in if let url = urls.first { store.receive(url); return true }; return false }
                .inspector(isPresented: $store.preferences.showInspector) { inspector.inspectorColumnWidth(min: 230, ideal: 265, max: 350) }
                .sheet(item: $editingApp) { app in EditAppView(app: app).environmentObject(store) }
                .onChange(of: store.selectedID) { _, _ in refreshLog() }
                .onChange(of: store.running) { _, _ in refreshLog() }
        }.onChange(of: store.preferences) { _, _ in store.save() }
    }
    private func symbol(for section: LibrarySection) -> String {
        switch section {
        case .all: return "square.grid.2x2"
        case .games: return "gamecontroller"
        case .programs: return "app"
        case .favorites: return "star"
        case .recent: return "clock"
        }
    }
    @ViewBuilder private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if currentSection == .favorites {
            ContentUnavailableView { Label("No favorites yet", systemImage: "star") } description: { Text("Star an app from its context menu or details to pin it here.") }
        } else if currentSection == .recent {
            ContentUnavailableView { Label("Nothing opened yet", systemImage: "clock") } description: { Text("Apps you run appear here, newest first.") }
        } else {
            ContentUnavailableView { Label("No apps yet", systemImage: "app") } description: { Text("Add a Windows .exe or .msi, or open one from Finder. Compatibility depends on the app and runtime.") } actions: { Button("Choose file...") { store.chooseFile() }.buttonStyle(.glassProminent) }
        }
    }
    @ViewBuilder private func appIcon(_ app: WindowsApp) -> some View { if let path = app.iconPath, let icon = NSImage(contentsOfFile: path) { Image(nsImage: icon).resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true) } }
    private func name(_ app: WindowsApp) -> some View {
        HStack(spacing: 9) {
            appIcon(app); Text(app.name).font(.headline).lineLimit(1)
            if app.favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).accessibilityLabel("Favorite") }
            if store.running.contains(app.id) { Circle().fill(.green).frame(width: 8, height: 8).accessibilityLabel("Running") }
        }
    }
    @ViewBuilder private func launchControls(_ app: WindowsApp) -> some View {
        if store.running.contains(app.id) {
            HStack(spacing: 8) {
                Button("Running") {}.disabled(true)
                Button("Stop") { store.stop(app) }
            }
        } else {
            Button("Open") { store.requestLaunch(app) }
        }
    }
    private func appCard(_ app: WindowsApp) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            name(app)
            Text(app.category.rawValue).font(.caption).foregroundStyle(.secondary)
            if let lastOpened = app.lastOpened, currentSection == .recent { Text(lastOpened.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
            launchControls(app).frame(maxWidth: .infinity).buttonStyle(.glass)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(store.selectedID == app.id ? Color.accentColor : .clear, lineWidth: 1.5)).contentShape(Rectangle()).onTapGesture { store.selectedID = app.id }.contextMenu { appMenu(app) }
    }
    private func appRow(_ app: WindowsApp) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) { name(app); Text(app.category.rawValue).font(.caption).foregroundStyle(.secondary) }
            Spacer(); launchControls(app)
        }.padding(.vertical, 17).contentShape(Rectangle()).onTapGesture { store.selectedID = app.id }.contextMenu { appMenu(app) }
    }
    @ViewBuilder private func appMenu(_ app: WindowsApp) -> some View {
        Button("Open") { store.requestLaunch(app) }.disabled(store.running.contains(app.id))
        if store.running.contains(app.id) { Button("Stop") { store.stop(app) } }
        Button("App details") { store.selectedID = app.id; store.preferences.showInspector = true }
        Button("Edit app...") { store.selectedID = app.id; editingApp = app }
        Button(app.favorite ? "Remove from favorites" : "Add to favorites") { store.toggleFavorite(app) }
        Divider()
        Button("Show in Finder") { store.revealAppInFinder(app) }
        Button("Show Windows drive") { store.revealEnvironment(app) }
        Button("Open app log") { store.revealLog(app) }
        Divider()
        Button("Remove from library", role: .destructive) { store.remove(app) }
    }
    private func refreshLog() { logPreview = store.selected.flatMap { store.logPreview(for: $0) } }
    @ViewBuilder private var inspector: some View {
        if let app = store.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    name(app)
                    LabeledContent("Environment", value: store.library.environment(for: app)?.name ?? "Missing")
                    LabeledContent("Category", value: app.category.rawValue)
                    if let lastOpened = app.lastOpened { LabeledContent("Last opened", value: lastOpened.formatted(date: .abbreviated, time: .shortened)) }
                    if !app.launchArguments.isEmpty { LabeledContent("Launch arguments", value: app.launchArguments) }
                    Text(app.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    launchControls(app).buttonStyle(.glassProminent)
                    Button("Edit app...") { editingApp = app }
                    Button(app.favorite ? "Remove from favorites" : "Add to favorites") { store.toggleFavorite(app) }
                    Button("Show in Finder") { store.revealAppInFinder(app) }
                    Button("Show Windows drive") { store.revealEnvironment(app) }
                    Button("Open app log") { store.revealLog(app) }
                    Button("Choose app icon...") { store.chooseIcon(for: app) }
                    if app.iconPath != nil { Button("Remove app icon") { store.removeIcon(for: app) } }
                    if let logPreview {
                        Divider()
                        HStack { Text("Recent log output").font(.subheadline); Spacer(); Button("Refresh") { refreshLog() } }
                        Text(logPreview).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    Button("Remove from library", role: .destructive) { store.remove(app) }
                    Text("Removing a library entry does not delete your Windows files or environment.").font(.caption).foregroundStyle(.secondary)
                }.padding(23)
            }.onAppear { refreshLog() }
        } else { ContentUnavailableView("Select an app", systemImage: "sidebar.right", description: Text("App details appear here.")) }
    }
}
