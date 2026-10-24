import AppKit
import Combine
import Foundation
import os

/// Reads every Now Playing client (not just the system's active one) through
/// a small Perl-hosted helper. macOS 15.4+ blocks direct MediaRemote access,
/// but /usr/bin/perl is still trusted, and the helper runs inside it.
final class MultiMediaService: ObservableObject {
    struct Client: Identifiable, Decodable {
        let bundle: String
        let pid: Int32?
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsed: Double?
        let rate: Double?
        let artwork: String?

        var id: String { bundle }
        var isPlaying: Bool { (rate ?? 0) > 0 }
    }

    struct Source: Identifiable {
        let client: Client
        let artwork: NSImage?
        let appIcon: NSImage?
        let appName: String

        var id: String { client.bundle }
    }

    @Published private(set) var sources: [Source] = []
    @Published private(set) var available = false

    private var scriptPath: String?
    private var dylibPath: String?
    private var isRefreshing = false
    private var started = false

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        guard let resources = Bundle.main.resourceURL else { return }
        let script = resources.appendingPathComponent("mediaremote-helper.pl").path
        let dylib = resources.appendingPathComponent("libIsletMediaRemote.dylib").path

        guard FileManager.default.fileExists(atPath: script),
              FileManager.default.fileExists(atPath: dylib) else {
            Logger.app.info("multi-media: helper not bundled")
            return
        }

        scriptPath = script
        dylibPath = dylib
        available = true
        refresh()
    }

    // MARK: - Fetching

    func refresh() {
        guard available, !isRefreshing,
              let scriptPath, let dylibPath else { return }
        isRefreshing = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptPath, dylibPath, "list"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try process.run()
            } catch {
                DispatchQueue.main.async { self?.isRefreshing = false }
                return
            }

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

            if !errorData.isEmpty, let text = String(data: errorData, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    print("multi-media: \(trimmed)")
                }
            }

            let clients = (try? JSONDecoder().decode([Client].self, from: data)) ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                self.apply(clients)
            }
        }
    }

    private func apply(_ clients: [Client]) {
        let mapped = clients.map { client -> Source in
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client.bundle)
            let appIcon = appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            let appName = appURL.map {
                FileManager.default.displayName(atPath: $0.path)
                    .replacingOccurrences(of: ".app", with: "")
            } ?? client.bundle

            let artwork = client.artwork
                .flatMap { Data(base64Encoded: $0) }
                .flatMap { NSImage(data: $0) }

            return Source(client: client, artwork: artwork, appIcon: appIcon, appName: appName)
        }
        .sorted { lhs, rhs in
            if lhs.client.isPlaying != rhs.client.isPlaying {
                return lhs.client.isPlaying
            }
            let left = lhs.client.title ?? lhs.appName
            let right = rhs.client.title ?? rhs.appName
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }

        sources = mapped

        if !mapped.isEmpty {
            Logger.app.info(
                "multi-media: \(mapped.count, privacy: .public) clients [\(mapped.map(\.client.bundle).joined(separator: ", "), privacy: .public)]"
            )
        }
    }

    // MARK: - Per-client commands

    func send(_ command: Int, to bundleID: String) {
        guard let scriptPath, let dylibPath else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptPath, dylibPath, "send", bundleID, "\(command)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refresh()
        }
    }
}
