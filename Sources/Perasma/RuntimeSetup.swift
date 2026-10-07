import SwiftUI
import AppKit
import CryptoKit
import PerasmaCore

private final class ComponentDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double, Int64, Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    init(progress: @escaping @Sendable (Double, Int64, Int64) -> Void) { self.progress = progress }
    func start(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session; session.downloadTask(with: url).resume()
        }
    }
    func cancel() { session?.invalidateAndCancel() }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0, totalBytesWritten, totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200, response.url?.scheme == "https" else { throw NSError(domain: "Download", code: 1, userInfo: [NSLocalizedDescriptionKey: "Publisher download failed."]) }
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: target)
            continuation?.resume(returning: target); continuation = nil
        } catch { continuation?.resume(throwing: error); continuation = nil }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.resume(throwing: error); continuation = nil }
        session.finishTasksAndInvalidate(); self.session = nil
    }
}

@MainActor final class RuntimeSetup: ObservableObject {
    @Published var busy = false
    @Published var status = "One setup flow for Wine with Mono and Gecko."
    @Published var component = "Ready to download"
    @Published var progress = 0.0
    @Published var transferred: Int64 = 0
    @Published var total: Int64 = 0
    @Published var downloadedWine: URL?
    @Published var mediaBusy = false
    @Published var mediaPackage: URL?
    @Published var mediaStatus = "Optional: GStreamer adds media playback for some Windows apps. Wine works without it. Its macOS installer is not signed with an Apple certificate, so macOS will ask you to review it yourself before anything is installed."
    @Published var graphicsStatus = "Experimental D3D10/11 via DXVK-macOS (non-async). No D3D9/12 support or M1 compatibility claim. Uses a separate environment; existing apps are unchanged."
    @Published var steamStatus = "Download the current Windows installer from Valve and add it to your library. Installation and login remain yours to review. Steam rendering is not verified on M1."
    @Published var graphicsEnvironmentID: UUID?
    private let graphicsURL = URL(string: "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3/dxvk-v1.10.3.tar.gz")!
    private let graphicsHash = "5644f5c02e8dc3e25171e6b7b5d16e927332b32136c6caf8e418e1192cc2e5d4"
    private let steamURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
    private let steamHash = "7d3654531c32d941b8cae81c4137fc542172bfa9635f169cb392f245a0a12bcb"
    private var activeDownloader: ComponentDownload?
    private let wineURL = URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-devel-11.18-osx64.tar.xz")!
    private let wineHash = "aa0ea4c82e636ae7bca2076387cb0a5affa26509ad13f119ecd0d62bd7ba6f82"
    private let mediaURL = URL(string: "https://gstreamer.freedesktop.org/data/pkg/osx/1.28.5/gstreamer-1.0-1.28.5-universal.pkg")!
    private let mediaHash = "0a8fc7a1cf8d7bac833ca0ebe2fd196a199c2465e810cd5b1e4b4f720c258f43"
    var mediaInstalled: Bool { FileManager.default.fileExists(atPath: "/Library/Frameworks/GStreamer.framework") }
    func setUpAll(store: LibraryStore) {
        guard !busy, !mediaBusy else { return }; busy = true
        Task {
            do {
                component = "1 of 3 · Wine, Mono and Gecko"; status = "Downloading from the WineHQ macOS package maintainer."
                let archive = try await download(wineURL, expected: wineHash, root: store.root, base: 0, weight: 0.75)
                component = "2 of 3 · Verify and prepare"; status = "Checking archive paths."
                let destination = store.root.appendingPathComponent("Runtimes/Wine-11.18", isDirectory: true)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let bundle = destination.appendingPathComponent("Wine Devel.app")
                if !FileManager.default.fileExists(atPath: bundle.path) {
                    let listing = try await command("/usr/bin/tar", ["-tf", archive.path])
                    guard listing.code == 0, listing.output.split(separator: "\n").allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") && $0.hasPrefix("Wine Devel.app/") }) else { throw setupError("Unsafe or unexpected archive contents. Nothing was installed.") }
                    let result = try await command("/usr/bin/tar", ["-xf", archive.path, "-C", destination.path])
                    guard result.code == 0 else { throw setupError("Wine extraction failed.") }
                    let metadata = try await command("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0081;00000000;Perasma;", bundle.path])
                    guard metadata.code == 0 else { throw setupError("Runtime security metadata could not be set. Setup stopped.") }
                }
                downloadedWine = bundle; progress = 0.85
                component = "3 of 3 · macOS approval"; status = "Checking system requirements."
                #if arch(arm64)
                let rosetta = try await command("/usr/bin/arch", ["-x86_64", "/usr/bin/true"])
                guard rosetta.code == 0 else { throw setupError("This Wine package needs Rosetta. Open the downloaded Wine app to use Apple's macOS installation prompt, then continue setup. Perasma does not accept Apple's license for you.") }
                #endif
                let executable = bundle.appendingPathComponent("Contents/Resources/wine/bin/wine")
                guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw setupError("The Wine executable is missing.") }
                let assessment = try await command("/usr/sbin/spctl", ["--assess", "--type", "execute", bundle.path])
                guard assessment.code == 0 else { throw setupError("Wine is downloaded and verified, but macOS did not approve the package. Review it in Finder and macOS Privacy & Security, then continue setup. Perasma will not remove quarantine or bypass Gatekeeper.") }
                store.preferences.runtimePath = executable.path; store.save(); progress = 1
                component = "Core setup complete"
                status = "Wine, Mono and Gecko are ready. App compatibility still needs testing. Media still needs your installer review. Experimental graphics and Steam installer preparation are available below; game compatibility is not verified."
            } catch { status = error.localizedDescription }
            busy = false
        }
    }
    func setUpMedia(store: LibraryStore) {
        guard !mediaBusy, !busy else { return }
        if mediaInstalled { mediaStatus = "GStreamer is already installed for all users."; return }
        mediaBusy = true
        Task {
            do {
                mediaStatus = "Downloading GStreamer from the GStreamer project. Nothing is installed yet."
                let package = try await download(mediaURL, expected: mediaHash, root: store.root, base: 0, weight: 1)
                mediaPackage = package
                mediaStatus = "Download verified against the pinned publisher SHA-256. The installer is not Apple-signed, so macOS will ask you to review it. Choose Review and open installer only if you want media playback; install for all users there. Perasma does not bypass this check."
            } catch { mediaStatus = error.localizedDescription }
            mediaBusy = false
        }
    }
    func openMediaInstaller() {
        guard let package = mediaPackage else { return }
        NSWorkspace.shared.open(package)
        mediaStatus = "macOS Installer is open with the verified download. Review the package there; installing it is your choice. Perasma does not bypass the macOS check."
    }
    func prepareGraphics(store: LibraryStore) {
        guard !busy, !mediaBusy, store.runtimeAvailable else { return }
        busy = true; component = "Experimental graphics · download"; progress = 0; transferred = 0; total = 0
        Task {
            var newPrefix: URL?
            do {
                status = "Downloading non-async DXVK-macOS from its maintainer."
                let archive = try await download(graphicsURL, expected: graphicsHash, root: store.root, base: 0, weight: 0.7)
                component = "Experimental graphics · prepare"
                let listing = try await command("/usr/bin/tar", ["-tf", archive.path])
                guard listing.code == 0, !listing.output.isEmpty,
                      listing.output.split(separator: "\n").allSatisfy({ ComponentPolicy.safeArchiveEntry(String($0), root: "dxvk-v1.10.3") }) else { throw setupError("Unexpected graphics archive paths. Nothing was applied.") }
                let types = try await command("/usr/bin/tar", ["-tvf", archive.path])
                guard types.code == 0, types.output.split(separator: "\n").allSatisfy({ $0.first == "-" || $0.first == "d" }) else { throw setupError("Graphics archive contains links or special files. Nothing was applied.") }
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: scratch) }
                let unpack = try await command("/usr/bin/tar", ["-xf", archive.path, "-C", scratch.path])
                guard unpack.code == 0 else { throw setupError("Graphics extraction failed.") }
                let environment = WindowsEnvironment(name: "Experimental D3D10/11", graphics: .dxvk)
                let prefix = LaunchPlan.prefix(root: store.root, id: environment.id); newPrefix = prefix
                try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
                let initialization = try await wineCommand(store: store, prefix: prefix, arguments: ["wineboot", "-u"])
                guard initialization.code == 0 else { throw setupError("Wine could not prepare the test environment. Existing apps were not changed.") }
                for (source, target) in [("x64", "system32"), ("x32", "syswow64")] {
                    let directory = prefix.appendingPathComponent("drive_c/windows/" + target)
                    guard FileManager.default.fileExists(atPath: directory.path) else { throw setupError("The runtime did not create a WoW64 environment. Graphics were not enabled.") }
                    for name in ComponentPolicy.graphicsDLLs {
                        let dll = scratch.appendingPathComponent("dxvk-v1.10.3/" + source + "/" + name)
                        let values = try dll.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw setupError("Unexpected graphics file type.") }
                        let destination = directory.appendingPathComponent(name)
                        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                        try FileManager.default.copyItem(at: dll, to: destination)
                        let metadata = try await command("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0081;00000000;Perasma;", destination.path])
                        guard metadata.code == 0 else { throw setupError("Graphics security metadata could not be set. Setup stopped.") }
                    }
                }
                store.library.environments.append(environment); store.save(); graphicsEnvironmentID = environment.id
                newPrefix = nil; progress = 1
                graphicsStatus = "Separate experimental environment prepared. Only d3d10core and d3d11 are overridden. Import a trusted app into Experimental D3D10/11 to test it. No M1 game run has been verified."
                status = "Experimental graphics preparation complete, not a compatibility test."
            } catch {
                if let newPrefix { try? FileManager.default.removeItem(at: newPrefix) }
                graphicsStatus = error.localizedDescription; status = "Graphics preparation stopped."
            }
            busy = false
        }
    }
    func prepareSteam(store: LibraryStore) {
        guard !busy, !mediaBusy, store.runtimeAvailable else { return }
        busy = true; component = "Steam installer · download"; progress = 0; transferred = 0; total = 0
        Task {
            do {
                status = "Downloading the current Windows installer from Valve. Nothing is run automatically."
                let installer = try await download(steamURL, expected: steamHash, root: store.root, base: 0, weight: 1)
                if let existing = store.library.apps.first(where: { $0.path == installer.path }) { store.selectedID = existing.id }
                else { store.add(url: installer, name: "Steam installer", category: .games, environmentID: graphicsEnvironmentID) }
                steamStatus = "Verified download added to the library. Open Steam installer there to review and install. After installation, add Steam.exe using the same environment. No helper replacement, old client, or update freeze is applied. Rendering and login need an M1 test."
                status = "Steam installer prepared. Steam itself is not installed or verified."
            } catch { steamStatus = error.localizedDescription; status = "Steam preparation stopped. A changed publisher file is rejected until reviewed." }
            busy = false
        }
    }
    private func wineCommand(store: LibraryStore, prefix: URL, arguments: [String]) async throws -> (code: Int32, output: String) {
        let executable = store.preferences.runtimePath
        return try await Task.detached(priority: .utility) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment; environment["WINEPREFIX"] = prefix.path; process.environment = environment
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
    // CI captures real transfer callbacks without installing or opening any component.
    func startCaptureDownload(media: Bool, root: URL) {
        guard CommandLine.arguments.contains("--capture-downloads"), !busy, !mediaBusy else { return }
        progress = 0; transferred = 0; total = 0
        busy = !media; mediaBusy = media
        component = "1 of 3 · Wine, Mono and Gecko"
        status = "Downloading from the WineHQ macOS package maintainer."
        if media { mediaStatus = "Downloading GStreamer from the GStreamer project. Nothing is installed yet." }
        Task {
            do { _ = try await download(media ? mediaURL : wineURL, expected: media ? mediaHash : wineHash, root: root, base: 0, weight: 1) }
            catch { if media { mediaStatus = error.localizedDescription } else { status = error.localizedDescription } }
            busy = false; mediaBusy = false
        }
    }
    func stopCaptureDownload() {
        guard CommandLine.arguments.contains("--capture-downloads") else { return }
        activeDownloader?.cancel()
    }
    private func download(_ url: URL, expected: String, root: URL, base: Double, weight: Double) async throws -> URL {
        let directory = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path), try await hash(target) == expected { progress = base + weight; transferred = 0; total = 0; return target }
        let downloader = ComponentDownload { [weak self] fraction, received, total in
            Task { @MainActor in self?.progress = base + fraction * weight; self?.transferred = received; self?.total = total }
        }
        activeDownloader = downloader
        defer { activeDownloader = nil }
        let temporary = try await downloader.start(url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard try await hash(temporary) == expected else { throw setupError("Checksum mismatch. Download rejected.") }
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: temporary, to: target)
        let quarantine = try await command("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0081;00000000;Perasma;", target.path])
        guard quarantine.code == 0 else { throw setupError("Download security metadata could not be set. Setup stopped.") }
        progress = base + weight; return target
    }
    private func hash(_ url: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            var digest = SHA256()
            while let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty { digest.update(data: block) }
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
    private func command(_ path: String, _ arguments: [String]) async throws -> (code: Int32, output: String) {
        try await Task.detached(priority: .utility) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
    private func setupError(_ message: String) -> NSError { NSError(domain: "RuntimeSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

struct RuntimeSetupView: View {
    @EnvironmentObject var store: LibraryStore
    @ObservedObject var setup: RuntimeSetup
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Windows components").font(.headline)
            Text("Wine with Mono and Gecko, downloaded directly from its publisher. macOS may ask for system approval.").font(.callout).foregroundStyle(.secondary)
            if setup.busy {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(setup.component); Spacer(); Text("\(Int(setup.progress * 100))%").monospacedDigit() }
                    ProgressView(value: setup.progress).tint(.accentColor)
                    if setup.total > 0 { Text("\(ByteCountFormatter.string(fromByteCount: setup.transferred, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: setup.total, countStyle: .file))").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Button(setup.downloadedWine == nil ? "Download and set up components" : "Continue setup") { setup.setUpAll(store: store) }.buttonStyle(.glassProminent).disabled(setup.busy || setup.mediaBusy)
            Text(setup.status).font(.callout).textSelection(.enabled)
            if let bundle = setup.downloadedWine { Button("Review Wine in Finder") { NSWorkspace.shared.activateFileViewerSelecting([bundle]) } }
            Divider()
            Text("Media support (optional)").font(.subheadline)
            if setup.mediaBusy {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: setup.progress).tint(.accentColor)
                    if setup.total > 0 { Text("\(ByteCountFormatter.string(fromByteCount: setup.transferred, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: setup.total, countStyle: .file))").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Button(setup.mediaPackage == nil ? "Download media support" : "Review and open installer") { if setup.mediaPackage == nil { setup.setUpMedia(store: store) } else { setup.openMediaInstaller() } }.disabled(setup.busy || setup.mediaBusy)
            Text(setup.mediaStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Downloads use pinned SHA-256 values. Wine and GStreamer values come from publisher checksums; DXVK and Steam pins were measured from their HTTPS publisher downloads. Gatekeeper is never bypassed. DXMT, D3D12 and automatic Steam setup are not ready. This is not support for every game.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Experimental graphics").font(.subheadline).id("integrations")
            Button("Prepare separate D3D10/11 environment") { setup.prepareGraphics(store: store) }.disabled(setup.busy || setup.mediaBusy || !store.runtimeAvailable)
            Text(setup.graphicsStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Link("DXVK-macOS source & limitations", destination: URL(string: "https://github.com/Gcenx/DXVK-macOS/releases/tag/v1.10.3")!).font(.caption)
            Divider()
            Text("Steam preparation").font(.subheadline)
            Button("Download and add Steam installer") { setup.prepareSteam(store: store) }.disabled(setup.busy || setup.mediaBusy || !store.runtimeAvailable)
            Text(setup.steamStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Link("Valve Steam download", destination: URL(string: "https://store.steampowered.com/about/")!).font(.caption)
            HStack {
                Link("Wine source & license", destination: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18")!)
                Link("GStreamer source", destination: URL(string: "https://gstreamer.freedesktop.org/download/")!)
            }.font(.caption)
        }
    }
}
