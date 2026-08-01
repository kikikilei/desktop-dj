import AppKit
import CoreImage
import Foundation

enum PlaybackCommand: String {
    case previous
    case togglePlayPause
    case next
}

final class NowPlayingService: @unchecked Sendable {
    private let executableURL: URL?
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    init() {
        var candidates: [String] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(
                resources
                    .appendingPathComponent("Bridge/bin/nowplaying-cli")
                    .path
            )
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/nowplaying-cli",
            "/usr/local/bin/nowplaying-cli"
        ])
        executableURL = candidates
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    func readSnapshot() -> NowPlayingSnapshot? {
        guard
            let output = run(arguments: ["get-raw"]),
            let data = output.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let title = string(raw, "kMRMediaRemoteNowPlayingInfoTitle")
        let artist = string(raw, "kMRMediaRemoteNowPlayingInfoArtist")
        let album = string(raw, "kMRMediaRemoteNowPlayingInfoAlbum")

        guard !title.isEmpty || !artist.isEmpty else {
            return nil
        }

        let artwork = image(
            fromBase64: string(raw, "kMRMediaRemoteNowPlayingInfoArtworkData")
        )

        return NowPlayingSnapshot(
            title: title.isEmpty ? "Unknown Track" : title,
            artist: artist.isEmpty ? "Unknown Artist" : artist,
            album: album,
            duration: number(raw, "kMRMediaRemoteNowPlayingInfoDuration"),
            elapsed: number(raw, "kMRMediaRemoteNowPlayingInfoElapsedTime"),
            playbackRate: number(raw, "kMRMediaRemoteNowPlayingInfoPlaybackRate"),
            artwork: artwork,
            sourceBundleIdentifier: string(
                raw,
                "kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"
            )
        )
    }

    func send(_ command: PlaybackCommand) {
        _ = run(arguments: [command.rawValue])
    }

    private func run(arguments: [String]) -> String? {
        guard let executableURL else {
            return nil
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = pipe
        // Must not be an undrained Pipe: anything the bridge writes to stderr
        // would fill the buffer and block it forever.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            // Drain stdout *before* waiting. `get-raw` returns base64 artwork
            // and easily exceeds the 64 KB pipe buffer, so a child blocked on
            // write() plus a parent blocked in waitUntilExit() deadlocks.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func string(_ dictionary: [String: Any], _ key: String) -> String {
        dictionary[key] as? String ?? ""
    }

    private func number(_ dictionary: [String: Any], _ key: String) -> Double {
        if let value = dictionary[key] as? NSNumber {
            return value.doubleValue
        }
        return 0
    }

    private func image(fromBase64 base64: String) -> NSImage? {
        guard
            !base64.isEmpty,
            let data = Data(base64Encoded: base64),
            let source = CIImage(data: data)
        else {
            return nil
        }

        let filter = CIFilter(name: "CIPixellate")
        filter?.setValue(source, forKey: kCIInputImageKey)
        filter?.setValue(7.0, forKey: kCIInputScaleKey)
        filter?.setValue(
            CIVector(x: source.extent.midX, y: source.extent.midY),
            forKey: kCIInputCenterKey
        )

        guard
            let output = filter?.outputImage?.cropped(to: source.extent),
            let cgImage = context.createCGImage(output, from: source.extent)
        else {
            return NSImage(data: data)
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: source.extent.width, height: source.extent.height)
        )
    }
}
