import AppKit
import Foundation

enum CatState {
    case sleeping
    case playing
    case switching
}

enum PreviewScenario {
    case playing
    case sleeping
    case switching
    case longTitle
    case noArtwork
    case lateProgress
}

struct NowPlayingSnapshot {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let elapsed: TimeInterval
    let playbackRate: Double
    let artwork: NSImage?
    let sourceBundleIdentifier: String

    var isPlaying: Bool {
        playbackRate > 0
    }

    var identity: String {
        // NetEase can briefly omit or revise album/duration metadata while
        // resuming playback. Title + artist is stable enough for deciding
        // whether the visible track actually changed.
        "\(title)|\(artist)"
    }
}
