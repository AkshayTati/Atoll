import CoreFoundation
import Foundation
import MediaRemoteShim

private func printNowPlaying(_ info: CFDictionary?) {
    guard let info, let dict = info as? [String: Any] else {
        print("NO_NOW_PLAYING")
        return
    }

    let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? "<unknown>"
    let artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "<unknown>"
    let album = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "<unknown>"
    let duration = dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? -1
    let elapsed = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? -1
    let rate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? -1
    let artwork = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

    print("MEDIAREMOTE_OK")
    print("title: \(title)")
    print("artist: \(artist)")
    print("album: \(album)")
    print(String(format: "duration: %.1f elapsed: %.1f rate: %.1f", duration, elapsed, rate))
    print("artwork: \(artwork?.count ?? 0) bytes")

    let keys = dict.keys.sorted().joined(separator: ", ")
    print("keys: \(keys)")
}

private func exitWithError(_ message: String, code: Int32) -> Never {
    print(message)
    exit(code)
}

let command = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "info"

guard islet_mr_available() else {
    exitWithError("MEDIAREMOTE_UNAVAILABLE", code: 2)
}

switch command {
case "info":
    islet_mr_request_now_playing({ info, _ in
        printNowPlaying(info)
        exit(0)
    }, nil)

    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        print("TIMEOUT")
        exit(3)
    }
    dispatchMain()

case "play", "pause", "toggle", "next", "prev":
    let code: Int32
    switch command {
    case "play": code = 0
    case "pause": code = 1
    case "toggle": code = 2
    case "next": code = 4
    default: code = 5
    }
    islet_mr_send_command(code)
    print("SENT \(command) (\(code))")
    usleep(250_000)
    exit(0)

default:
    print("usage: mediaspike [info|play|pause|toggle|next|prev]")
    exit(1)
}
