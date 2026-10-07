import SwiftUI
import AppKit
import PerasmaCore

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var category: String? = "All apps"
    private var categoryName: String { category ?? "All apps" }
    @State private var search = ""
    private var apps: [WindowsApp] { store.library.apps.filter { app in (categoryName == "All apps" || categoryName == "Recently opened" || app.category.rawValue == categoryName) && (search.isEmpty || app.name.localizedCaseInsensitiveContains(search)) && (categoryName != "Recently opened" || app.lastOpened != nil) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var body: some View {
        NavigationSplitView {
            List(selection: $category) {
                Section("Library") { ForEach(["All apps", "Games", "Programs", "Recently opened"], id: \.self) { value in Text(value).tag(value) } }
            }.navigationSplitViewColumnWidth(min: 170, ideal: 205, max: 250)
        } detail: {
            VStack(alignment: .leading, spacing: 20) {
                HStack { VStack(alignment: .leading, spacing: 6) { Text(categoryName).font(.largeTitle.bold()); Text("Your Windows apps, in one place.").foregroundStyle(.secondary) }; Spacer(); Picker("Layout", selection: $store.preferences.layout) { ForEach(LibraryLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().pickerStyle(.segmented).frame(width: 130) }
                if !store.runtimeAvailable {
                    HStack(spacing: 12) { Image(systemName: "info.circle"); Text("Set up Windows components in Settings before running apps.").font(.callout); Spacer(); SettingsLink { Text("Settings") } }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
                if apps.isEmpty {
                    ContentUnavailableView { Label("No apps yet", systemImage: "app") } description: { Text("Add a Windows .exe or .msi, or open one from Finder. Compatibility depends on the app and runtime.") } actions: { Button("Choose file...") { store.chooseFile() }.buttonStyle(.glassProminent) }
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
        }.onChange(of: store.preferences) { _, _ in store.save() }
    }
    @ViewBuilder private func appIcon(_ app: WindowsApp) -> some View { if let path = app.iconPath, let icon = NSImage(contentsOfFile: path) { Image(nsImage: icon).resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true) } }
    private func name(_ app: WindowsApp) -> some View { HStack(spacing: 9) { appIcon(app); Text(app.name).font(.headline).lineLimit(1) } }
    private func appCard(_ app: WindowsApp) -> some View {
        VStack(alignment: .leading, spacing: 14) { name(app); Text(app.category.rawValue).font(.caption).foregroundStyle(.secondary); Button(store.running.contains(app.id) ? "Running" : "Open") { store.requestLaunch(app) }.disabled(store.running.contains(app.id)).frame(maxWidth: .infinity).buttonStyle(.glass) }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(store.selectedID == app.id ? Color.accentColor : .clear, lineWidth: 1.5)).contentShape(Rectangle()).onTapGesture { store.selectedID = app.id }.contextMenu { Button("App details") { store.selectedID = app.id; store.preferences.showInspector = true }; Button("Open") { store.requestLaunch(app) } }
    }
    private func appRow(_ app: WindowsApp) -> some View { HStack { VStack(alignment: .leading, spacing: 6) { name(app); Text(app.category.rawValue).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Open") { store.requestLaunch(app) }.disabled(store.running.contains(app.id)) }.padding(.vertical, 17).contentShape(Rectangle()).onTapGesture { store.selectedID = app.id } }
    @ViewBuilder private var inspector: some View {
        if let app = store.selected {
            VStack(alignment: .leading, spacing: 23) { name(app); LabeledContent("Environment", value: store.library.environments.first(where: { $0.id == app.environmentID })?.name ?? "Missing"); LabeledContent("Category", value: app.category.rawValue); Text(app.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled); Button("Open app") { store.requestLaunch(app) }.buttonStyle(.glassProminent).disabled(store.running.contains(app.id)); Button("Show Windows drive") { store.revealEnvironment(app) }; Button("Open app log") { store.revealLog(app) }; Button("Choose app icon...") { store.chooseIcon(for: app) }; Spacer(); Button("Remove from library", role: .destructive) { store.remove(app) }; Text("Removing a library entry does not delete your Windows files or environment.").font(.caption).foregroundStyle(.secondary) }.padding(23)
        } else { ContentUnavailableView("Select an app", systemImage: "sidebar.right", description: Text("App details appear here.")) }
    }
}
