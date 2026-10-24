import AppKit
import Combine
import CoreImage
import Foundation
import os

/// Now-playing integration.
///
/// Since macOS 15.4, MediaRemote refuses to talk to normal apps. The
/// `media-control` CLI routes through `/usr/bin/perl`, which macOS still
/// trusts, and streams JSON lines we can consume. It also sends transport
/// commands for us.
final class MediaService: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var sourceName = ""
    @Published private(set) var sourceIcon: NSImage?
    @Published private(set) var sourceBundleID = ""
    @Published private(set) var accentColor = NSColor(calibratedRed: 0.12, green: 0.85, blue: 1.0, alpha: 1)
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var helperMissing = false

    var hasTrack: Bool { !title.isEmpty }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    private var cliPath: String?
    private var streamProcess: Process?
    private var lineBuffer = Data()
    private var started = false
    private var stopping = false

    private var state: [String: Any] = [:]
    private var lastTitle = ""
    private var lastArtworkData: Data?
    private var lastBundleID = ""

    private var baseElapsed: TimeInterval = 0
    private var baseDate = Date()
    private var playbackRate: Double = 0
    private var tickTimer: Timer?
    private var lastPlaying = false
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
    private var accentGeneration = 0

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        cliPath = locateCLI()
        guard cliPath != nil else {
            helperMissing = true
            print("media: media-control not found")
            return
        }
        startStream()
    }

    func stop() {
        stopping = true
        streamProcess?.terminate()
        streamProcess = nil
        stopTicking()
    }

    /// The stream is push-based; this only restarts it if it died.
    func refresh() {
        if streamProcess == nil, started, !stopping {
            startStream()
        }
    }

    // MARK: - Transport

    func togglePlayPause() {
        send(2)
    }

    func play() {
        send(0)
    }

    func pause() {
        send(1)
    }

    func next() {
        send(4)
    }

    func previous() {
        send(5)
    }

    private func send(_ command: Int) {
        runCLI(["send", "\(command)"])
    }

    // MARK: - media-control child process

    private func locateCLI() -> String? {
        let candidates = [
            "/opt/homebrew/bin/media-control",
            "/usr/local/bin/media-control",
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/media-control").path
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func startStream() {
        guard let cliPath, streamProcess == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["stream", "--debounce=100"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                print("media-control: \(trimmed)")
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                self.streamProcess = nil
                guard self.started, !self.stopping else { return }
                print("media: stream exited (\(proc.terminationStatus)); restarting")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.startStream()
                }
            }
        }

        do {
            try process.run()
            streamProcess = process
            print("media: streaming via \(cliPath)")
        } catch {
            print("media: failed to start stream: \(error)")
            helperMissing = true
        }
    }

    private func runCLI(_ arguments: [String]) {
        guard let cliPath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            print("media: command \(arguments) failed: \(error)")
        }
    }

    private func consume(_ data: Data) {
        lineBuffer.append(data)

        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer[lineBuffer.startIndex..<newline]
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)

            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else {
                continue
            }

            let diff = object["diff"] as? Bool ?? false
            DispatchQueue.main.async { [weak self] in
                self?.apply(payload, diff: diff)
            }
        }
    }

    // MARK: - State

    private func apply(_ payload: [String: Any], diff: Bool) {
        if diff {
            for (key, value) in payload {
                if value is NSNull {
                    state.removeValue(forKey: key)
                } else {
                    state[key] = value
                }
            }
        } else {
            state = payload
        }

        applyState()
    }

    private func applyState() {
        let newTitle = state["title"] as? String ?? ""

        guard !newTitle.isEmpty else {
            clear()
            return
        }

        title = newTitle
        artist = state["artist"] as? String ?? ""
        album = state["album"] as? String ?? ""
        duration = state["duration"] as? Double ?? 0

        let rawElapsed = state["elapsedTime"] as? Double ?? 0
        playbackRate = state["playbackRate"] as? Double ?? 0
        let playing = state["playing"] as? Bool ?? (playbackRate > 0)

        baseElapsed = rawElapsed
        baseDate = Date()
        elapsed = rawElapsed
        isPlaying = playing
        if playing != lastPlaying {
            print("media: playing=\(playing)")
            Logger.app.info("media: playing=\(playing, privacy: .public)")
            lastPlaying = playing
        }

        updateArtwork(titleChanged: newTitle != lastTitle)
        if newTitle != lastTitle {
            let bundle = state["bundleIdentifier"] as? String ?? ""
            print("media: \(newTitle) — \(artist) [\(bundle)] artwork=\(artwork != nil)")
            Logger.app.info("media: \(newTitle, privacy: .public) — \(self.artist, privacy: .public) [\(bundle, privacy: .public)]")
        }
        lastTitle = newTitle

        updateSource()

        if isPlaying {
            startTicking()
        } else {
            stopTicking()
        }
    }

    private func updateArtwork(titleChanged: Bool) {
        if let encoded = state["artworkData"] as? String,
           let data = Data(base64Encoded: encoded) {
            if data != lastArtworkData {
                lastArtworkData = data
                artwork = NSImage(data: data)
                if let artwork {
                    Logger.app.info("media: artwork \(data.count, privacy: .public) bytes \(artwork.size.width, privacy: .public)x\(artwork.size.height, privacy: .public)")
                    updateAccent(from: artwork)
                }
            }
        } else if titleChanged {
            // Artwork can briefly disappear while a track is changing. Only
            // drop it when the track itself changed.
            artwork = nil
            lastArtworkData = nil
            accentGeneration += 1
            accentColor = NSColor(calibratedRed: 0.12, green: 0.85, blue: 1.0, alpha: 1)
        }
    }

    private func updateAccent(from image: NSImage) {
        accentGeneration += 1
        let generation = accentGeneration

        guard let tiff = image.tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let extent = CIVector(cgRect: ciImage.extent)
            guard let filter = CIFilter(
                name: "CIAreaAverage",
                parameters: [
                    kCIInputImageKey: ciImage,
                    kCIInputExtentKey: extent
                ]
            ), let output = filter.outputImage else {
                return
            }

            var bitmap = [UInt8](repeating: 0, count: 4)
            self.ciContext.render(
                output,
                toBitmap: &bitmap,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: nil
            )

            let raw = NSColor(
                calibratedRed: CGFloat(bitmap[0]) / 255,
                green: CGFloat(bitmap[1]) / 255,
                blue: CGFloat(bitmap[2]) / 255,
                alpha: 1
            )
            guard let rgb = raw.usingColorSpace(.deviceRGB) else { return }

            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

            let accent: NSColor
            if saturation < 0.06 {
                accent = NSColor(calibratedRed: 0.12, green: 0.85, blue: 1.0, alpha: 1)
            } else {
                accent = NSColor(
                    calibratedHue: hue,
                    saturation: min(max(saturation * 1.5, 0.45), 1),
                    brightness: min(max(brightness * 1.15, 0.6), 1),
                    alpha: 1
                )
            }

            DispatchQueue.main.async {
                guard generation == self.accentGeneration else { return }
                self.accentColor = accent
            }
        }
    }

    private func updateSource() {
        let bundleID = state["bundleIdentifier"] as? String ?? ""
        sourceBundleID = bundleID
        guard bundleID != lastBundleID else { return }
        lastBundleID = bundleID

        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            sourceName = ""
            sourceIcon = nil
            return
        }

        sourceName = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        sourceIcon = NSWorkspace.shared.icon(forFile: url.path)
    }

    private func clear() {
        title = ""
        artist = ""
        album = ""
        artwork = nil
        sourceName = ""
        sourceIcon = nil
        sourceBundleID = ""
        isPlaying = false
        duration = 0
        elapsed = 0
        baseElapsed = 0
        playbackRate = 0
        lastTitle = ""
        lastArtworkData = nil
        lastBundleID = ""
        lastPlaying = false
        accentGeneration += 1
        accentColor = NSColor(calibratedRed: 0.12, green: 0.85, blue: 1.0, alpha: 1)
        state = [:]
        stopTicking()
    }

    // MARK: - Elapsed time

    private func startTicking() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard isPlaying, playbackRate > 0 else { return }
        let projected = baseElapsed + Date().timeIntervalSince(baseDate) * playbackRate
        elapsed = duration > 0 ? min(projected, duration) : projected
    }
}
