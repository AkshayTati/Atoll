import AppKit
import Combine
import CoreFoundation
import Foundation
import MediaRemoteShim

/// Reads the system "Now Playing" state through the private MediaRemote
/// framework and exposes it to SwiftUI.
final class MediaService: ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var elapsed: TimeInterval = 0

    var hasTrack: Bool { !title.isEmpty }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    private var baseElapsed: TimeInterval = 0
    private var baseDate = Date()
    private var playbackRate: Double = 0
    private var isRequestInFlight = false
    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var lastArtworkData: Data?
    private var started = false

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        installNotificationObservers()
        refresh()

        let poll = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll
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

    private func send(_ command: Int32) {
        guard islet_mr_available() else { return }
        islet_mr_send_command(command)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Fetching

    func refresh() {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true

        let context = Unmanaged.passUnretained(self).toOpaque()
        islet_mr_request_now_playing({ info, rawContext in
            guard let rawContext else { return }
            let service = Unmanaged<MediaService>.fromOpaque(rawContext).takeUnretainedValue()
            service.receive(info)
        }, context)
    }

    private func receive(_ info: CFDictionary?) {
        let dict = info as? [String: Any]

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRequestInFlight = false
            self.apply(dict)
        }
    }

    private func apply(_ dict: [String: Any]?) {
        guard let dict, !dict.isEmpty else {
            clear()
            return
        }

        title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        album = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        duration = dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
        let rawElapsed = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
        playbackRate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0

        baseElapsed = rawElapsed
        baseDate = Date()
        elapsed = rawElapsed
        isPlaying = playbackRate > 0

        let artworkData = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        if artworkData != lastArtworkData {
            lastArtworkData = artworkData
            if let artworkData, let image = NSImage(data: artworkData) {
                artwork = image
            } else {
                artwork = nil
            }
        }

        if isPlaying {
            startTicking()
        } else {
            stopTicking()
        }
    }

    private func clear() {
        title = ""
        artist = ""
        album = ""
        artwork = nil
        isPlaying = false
        duration = 0
        elapsed = 0
        baseElapsed = 0
        playbackRate = 0
        lastArtworkData = nil
        stopTicking()
    }

    // MARK: - Notifications

    private func installNotificationObservers() {
        guard islet_mr_register_notifications() else {
            print("media: notifications unavailable, polling only")
            return
        }

        print("media: notifications registered")

        let names = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        ]

        for name in names {
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
        }
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
