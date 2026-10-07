import SwiftUI
import AppKit
import CryptoKit

@MainActor final class RuntimeSetup: ObservableObject {
    @Published var busy = false
    @Published var status = "Download components from their original publishers."
    @Published var downloadedWine: URL?
    private let wineURL = URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-devel-11.18-osx64.tar.xz")!
    private let wineHash = "aa0ea4c82e636ae7bca2076387cb0a5affa26509ad13f119ecd0d62bd7ba6f82"
    private let mediaURL = URL(string: "https://gstreamer.freedesktop.org/data/pkg/osx/1.28.5/gstreamer-1.0-1.28.5-universal.pkg")!
    private let mediaHash = "0a8fc7a1cf8d7bac833ca0ebe2fd196a199c2465e810cd5b1e4b4f720c258f43"
    func installWine(store: LibraryStore) {
        guard !busy else { return }; busy = true
        Task {
            do {
                status = "Downloading Wine 11.18 from the macOS package maintainer..."
                let archive = try await download(wineURL, expected: wineHash, root: store.root)
                let destination = store.root.appendingPathComponent("Runtimes/Wine-11.18", isDirectory: true)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                status = "Checking archive paths and extracting Wine..."
                let listing = try await command("/usr/bin/tar", ["-tf", archive.path])
                guard listing.code == 0, listing.output.split(separator: "\n").allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") && $0.hasPrefix("Wine Devel.app/") }) else { throw setupError("Unsafe or unexpected archive contents. Nothing was installed.") }
                let result = try await command("/usr/bin/tar", ["-xf", archive.path, "-C", destination.path])
                guard result.code == 0 else { throw setupError("Archive extraction failed.") }
                let bundle = destination.appendingPathComponent("Wine Devel.app")
                let metadata = try await command("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0081;00000000;Perasma;", bundle.path])
                guard metadata.code == 0 else { throw setupError("Runtime security metadata could not be set. Setup stopped.") }
                downloadedWine = bundle
                let executable = bundle.appendingPathComponent("Contents/Resources/wine/bin/wine")
                guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw setupError("The Wine executable is missing.") }
                status = "Checking macOS security approval..."
                let assessment = try await command("/usr/sbin/spctl", ["--assess", "--type", "execute", bundle.path])
                guard assessment.code == 0 else { throw setupError("Wine downloaded and its SHA-256 verified. macOS did not approve this package. Perasma will not remove quarantine or bypass Gatekeeper. Review the package in Finder and macOS security settings, or choose an already approved runtime.") }
                #if arch(arm64)
                let rosetta = try await command("/usr/bin/arch", ["-x86_64", "/usr/bin/true"])
                guard rosetta.code == 0 else { throw setupError("This Wine package needs Apple's Rosetta. Install it using Apple's macOS prompt, then retry setup. Perasma does not accept Apple's license for you.") }
                #endif
                guard FileManager.default.fileExists(atPath: "/Library/Frameworks/GStreamer.framework") else { throw setupError("Wine is downloaded. Install the GStreamer runtime below for all users, then retry setup.") }
                store.preferences.runtimePath = executable.path; store.save()
                status = "Wine configured. Windows-app compatibility and graphics performance still need testing on this Mac."
            } catch { status = error.localizedDescription }
            busy = false
        }
    }
    func downloadMedia(root: URL) {
        guard !busy else { return }; busy = true
        Task {
            do {
                status = "Downloading GStreamer from its project server..."
                let package = try await download(mediaURL, expected: mediaHash, root: root)
                let signature = try await command("/usr/sbin/pkgutil", ["--check-signature", package.path])
                guard signature.code == 0 else { throw setupError("GStreamer checksum matched, but macOS could not verify the installer signature. Installation was not started.") }
                NSWorkspace.shared.open(package)
                status = "Verified installer opened. Review its license and approve installation for all users in macOS Installer. Then retry Wine setup."
            } catch { status = error.localizedDescription }; busy = false
        }
    }
    private func download(_ url: URL, expected: String, root: URL) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.url?.scheme == "https" else { throw setupError("The publisher's download failed.") }
        let hash = try await Task.detached(priority: .utility) { () throws -> String in
            let handle = try FileHandle(forReadingFrom: temporary); defer { try? handle.close() }
            var digest = SHA256()
            while let block = try handle.read(upToCount: 1024 * 1024), !block.isEmpty { digest.update(data: block) }
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
        guard hash == expected else { throw setupError("Checksum mismatch. The download was rejected.") }
        let directory = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: temporary, to: target)
        let quarantine = try await command("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0081;00000000;Perasma;", target.path])
        guard quarantine.code == 0 else { throw setupError("Download security metadata could not be set. Setup stopped.") }
        return target
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
    @StateObject private var setup = RuntimeSetup()
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Windows components").font(.headline)
            Text("Downloaded on demand, never included in Perasma. Pinned versions are checked against publisher SHA-256 values.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Download and set up Wine") { setup.installWine(store: store) }.buttonStyle(.glassProminent)
                Button("Get GStreamer") { setup.downloadMedia(root: store.root) }.buttonStyle(.glass)
            }.disabled(setup.busy)
            if setup.busy { ProgressView().controlSize(.small) }
            Text(setup.status).font(.caption).textSelection(.enabled)
            if let bundle = setup.downloadedWine { Button("Show downloaded Wine") { NSWorkspace.shared.activateFileViewerSelecting([bundle]) } }
            HStack {
                Link("Wine source & license", destination: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18")!)
                Link("GStreamer", destination: URL(string: "https://gstreamer.freedesktop.org/download/")!)
            }.font(.caption)
            Divider()
            Text("Graphics and games").font(.headline)
            Text("Extra graphics layers depend on the engine and game. Apple D3DMetal needs Apple's download and license review. Automatic integration is not available yet.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Link("Apple game toolkit", destination: URL(string: "https://developer.apple.com/download/all/?q=Evaluation%20environment%20for%20Windows%20games")!)
                Link("DXMT releases", destination: URL(string: "https://github.com/3Shain/dxmt/releases/tag/v0.80")!)
                Link("Steam", destination: URL(string: "https://store.steampowered.com/about/")!)
            }.font(.caption)
        }
    }
}
