import SwiftUI
import AppKit
import CryptoKit

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
                status = "Wine, Mono and Gecko are ready. App compatibility still needs testing. Extra game graphics, media playback and Steam setup are not integrated yet."
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
    private func download(_ url: URL, expected: String, root: URL, base: Double, weight: Double) async throws -> URL {
        let directory = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path), try await hash(target) == expected { progress = base + weight; transferred = 0; total = 0; return target }
        let downloader = ComponentDownload { [weak self] fraction, received, total in
            Task { @MainActor in self?.progress = base + fraction * weight; self?.transferred = received; self?.total = total }
        }
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
            Text("Downloads are checked against pinned publisher SHA-256 values. Gatekeeper is never bypassed. Extra graphics layers and Steam automation are still being developed; this is core setup, not support for every game.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("Wine source & license", destination: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18")!)
                Link("GStreamer source", destination: URL(string: "https://gstreamer.freedesktop.org/download/")!)
            }.font(.caption)
        }
    }
}
