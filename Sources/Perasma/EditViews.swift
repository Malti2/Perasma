import SwiftUI
import AppKit
import PerasmaCore

struct EditAppView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var category: AppCategory
    @State private var environmentID: UUID
    @State private var favorite: Bool
    @State private var launchArguments: String
    private let app: WindowsApp
    init(app: WindowsApp) {
        self.app = app
        _name = State(initialValue: app.name)
        _category = State(initialValue: app.category)
        _environmentID = State(initialValue: app.environmentID)
        _favorite = State(initialValue: app.favorite)
        _launchArguments = State(initialValue: app.launchArguments)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Edit app").font(.title.bold())
            Text(app.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Form {
                TextField("Name", text: $name)
                Picker("Category", selection: $category) { ForEach(AppCategory.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Environment", selection: $environmentID) { ForEach(store.library.environments) { Text($0.name).tag($0.id) } }
                Toggle("Favorite", isOn: $favorite)
                TextField("Launch arguments", text: $launchArguments, prompt: Text("-windowed -dx11"))
            }
            Text("Launch arguments are passed to the app every time it starts. Use quotes for values with spaces, for example -name \"My Profile\". Moving an app to another environment changes which Windows settings and files it sees.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    var edited = app
                    edited.name = name; edited.category = category; edited.environmentID = environmentID; edited.favorite = favorite; edited.launchArguments = launchArguments
                    store.update(edited); dismiss()
                }.buttonStyle(.glassProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(32).frame(width: 520)
    }
}

struct EnvironmentsView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var newName = ""
    @State private var pendingFileDeletion: WindowsEnvironment?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(store.library.environments) { environment in environmentRow(environment) }
            HStack {
                TextField("New environment name", text: $newName)
                Button("Create environment") {
                    store.createEnvironment(name: newName); newName = ""
                }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Deleting an environment moves its apps to the first remaining environment. Deleting its files moves the Windows drive to the Trash; that cannot be undone from Perasma.").font(.caption).foregroundStyle(.secondary)
        }
        .alert("Delete this environment's files?", isPresented: Binding(get: { pendingFileDeletion != nil }, set: { if !$0 { pendingFileDeletion = nil } })) {
            Button("Cancel", role: .cancel) { pendingFileDeletion = nil }
            Button("Move to Trash", role: .destructive) { if let environment = pendingFileDeletion { store.deleteEnvironmentFiles(environment) }; pendingFileDeletion = nil }
        } message: { Text("The Windows drive of \(pendingFileDeletion?.name ?? "this environment") is moved to the Trash. Apps in it will recreate an empty drive on next launch.") }
    }
    private func environmentRow(_ environment: WindowsEnvironment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: Binding(get: { environment.name }, set: { store.renameEnvironment(environment, to: $0) })).labelsHidden()
                Spacer()
                Text("\(store.library.apps(in: environment.id).count) apps").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Picker("Graphics", selection: Binding(get: { environment.graphics }, set: { store.setGraphics($0, for: environment) })) {
                    Text("Default").tag(Optional<GraphicsBackend>.none)
                    ForEach(GraphicsBackend.allCases) { Text($0.label).tag(Optional($0)) }
                }.labelsHidden().frame(width: 190)
                Spacer()
                Button("Show in Finder") { store.revealEnvironment(environment) }
                Button("Delete files...") { pendingFileDeletion = environment }
                Button("Delete", role: .destructive) { store.deleteEnvironment(environment) }
            }
        }.padding(.vertical, 4)
    }
}
