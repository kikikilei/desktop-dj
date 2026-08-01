import AppKit
import CoreImage
import Foundation

enum PlaybackCommand: String {
    case previous
    case togglePlayPause
    case next
}

enum BridgeLocation: String, Sendable {
    case embedded = "Embedded in app"
    case homebrewAppleSilicon = "Homebrew (Apple Silicon)"
    case homebrewIntel = "Homebrew (Intel)"
    case missing = "Not found"
}

struct BridgeDiagnostic: Sendable {
    let location: BridgeLocation
    let found: Bool
    let executable: Bool
    let exitCode: Int32?
    let responseTime: TimeInterval
    let responseBytes: Int
    let timedOut: Bool
    let jsonValid: Bool
    let titleAvailable: Bool
    let artistAvailable: Bool
    let playbackRateAvailable: Bool
    let playbackRate: Double?
    let durationAvailable: Bool
    let artworkAvailable: Bool
    let sourceBundleIdentifier: String
    let error: String?
}

struct NowPlayingMetadata: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let elapsed: TimeInterval
    let playbackRate: Double

    var identity: String { "\(title)|\(artist)" }
}

final class NowPlayingService: @unchecked Sendable {
    private let executableURL: URL?
    private let bridgeLocation: BridgeLocation
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let runner: ProcessRunner
    private let timeout: TimeInterval
    private var cachedIdentity = ""
    private var cachedArtwork: NSImage?
    private var cachedSourceBundleIdentifier = ""
    private var lastArtworkAttemptDate: Date?

    init(
        executableCandidates: [(URL, BridgeLocation)]? = nil,
        runner: ProcessRunner = ProcessRunner(),
        timeout: TimeInterval = 2.5
    ) {
        let defaultCandidates: [(URL, BridgeLocation)] = [
            (
                Bundle.main.resourceURL?
                    .appendingPathComponent("Bridge/bin/nowplaying-cli")
                    ?? URL(fileURLWithPath: "/missing/embedded/nowplaying-cli"),
                .embedded
            ),
            (
                URL(fileURLWithPath: "/opt/homebrew/bin/nowplaying-cli"),
                .homebrewAppleSilicon
            ),
            (
                URL(fileURLWithPath: "/usr/local/bin/nowplaying-cli"),
                .homebrewIntel
            )
        ]
        let candidates = executableCandidates ?? defaultCandidates
        self.runner = runner
        self.timeout = timeout

        if let match = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.0.path)
        }) {
            executableURL = match.0
            bridgeLocation = match.1
        } else {
            executableURL = nil
            bridgeLocation = .missing
        }
    }

    func readSnapshot() -> NowPlayingSnapshot? {
        guard
            let metadata = readMetadata(),
            !metadata.title.isEmpty || !metadata.artist.isEmpty
        else {
            return nil
        }

        let shouldRefreshArtwork = metadata.identity != cachedIdentity
            || (cachedArtwork == nil && shouldRetryArtwork())
        if shouldRefreshArtwork {
            cachedIdentity = metadata.identity
            lastArtworkAttemptDate = Date()
            refreshArtworkAndSource()
        }

        return NowPlayingSnapshot(
            title: metadata.title.isEmpty ? "Unknown Track" : metadata.title,
            artist: metadata.artist.isEmpty ? "Unknown Artist" : metadata.artist,
            album: metadata.album,
            duration: metadata.duration,
            elapsed: metadata.elapsed,
            playbackRate: metadata.playbackRate,
            artwork: cachedArtwork,
            sourceBundleIdentifier: cachedSourceBundleIdentifier
        )
    }

    func send(_ command: PlaybackCommand) {
        _ = execute(arguments: [command.rawValue])
    }

    func diagnose() -> BridgeDiagnostic {
        guard let executableURL else {
            return BridgeDiagnostic(
                location: .missing,
                found: false,
                executable: false,
                exitCode: nil,
                responseTime: 0,
                responseBytes: 0,
                timedOut: false,
                jsonValid: false,
                titleAvailable: false,
                artistAvailable: false,
                playbackRateAvailable: false,
                playbackRate: nil,
                durationAvailable: false,
                artworkAvailable: false,
                sourceBundleIdentifier: "",
                error: "No usable nowplaying-cli executable was found."
            )
        }

        let result = runner.run(
            executableURL: executableURL,
            arguments: ["get-raw"],
            timeout: timeout
        )
        let raw = Self.parseRawJSON(result.stdout)
        let playbackRate = raw?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber
        let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
        let error: String?
        if let launchError = result.launchError {
            error = launchError
        } else if result.timedOut {
            error = "Bridge did not respond within \(String(format: "%.1f", timeout)) seconds."
        } else if result.exitCode != 0 {
            error = stderr.isEmpty ? "Bridge exited with a non-zero status." : stderr
        } else if raw == nil {
            error = "Bridge output was not valid JSON."
        } else {
            error = nil
        }

        return BridgeDiagnostic(
            location: bridgeLocation,
            found: FileManager.default.fileExists(atPath: executableURL.path),
            executable: FileManager.default.isExecutableFile(atPath: executableURL.path),
            exitCode: result.exitCode,
            responseTime: result.duration,
            responseBytes: result.stdout.count,
            timedOut: result.timedOut,
            jsonValid: raw != nil,
            titleAvailable: Self.hasValue(raw, "kMRMediaRemoteNowPlayingInfoTitle"),
            artistAvailable: Self.hasValue(raw, "kMRMediaRemoteNowPlayingInfoArtist"),
            playbackRateAvailable: playbackRate != nil,
            playbackRate: playbackRate?.doubleValue,
            durationAvailable: raw?["kMRMediaRemoteNowPlayingInfoDuration"] is NSNumber,
            artworkAvailable: Self.hasValue(raw, "kMRMediaRemoteNowPlayingInfoArtworkData"),
            sourceBundleIdentifier: raw?["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String ?? "",
            error: error
        )
    }

    static func parseMetadataOutput(_ data: Data) -> NowPlayingMetadata? {
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        var lines = output.components(separatedBy: .newlines)
        if lines.last == "" { lines.removeLast() }
        guard lines.count >= 6 else { return nil }
        let values = lines.prefix(6).map(normalizedValue)
        return NowPlayingMetadata(
            title: values[0],
            artist: values[1],
            album: values[2],
            duration: Double(values[3]) ?? 0,
            elapsed: Double(values[4]) ?? 0,
            playbackRate: Double(values[5]) ?? 0
        )
    }

    private func readMetadata() -> NowPlayingMetadata? {
        let result = execute(arguments: [
            "get", "title", "artist", "album", "duration", "elapsedTime", "playbackRate"
        ])
        guard result.exitCode == 0, !result.timedOut else { return nil }
        return Self.parseMetadataOutput(result.stdout)
    }

    private func refreshArtworkAndSource() {
        let result = execute(arguments: ["get-raw"])
        guard
            result.exitCode == 0,
            !result.timedOut,
            let raw = Self.parseRawJSON(result.stdout)
        else {
            cachedArtwork = nil
            cachedSourceBundleIdentifier = ""
            return
        }
        cachedArtwork = image(
            fromBase64: Self.string(raw, "kMRMediaRemoteNowPlayingInfoArtworkData")
        )
        cachedSourceBundleIdentifier = Self.string(
            raw,
            "kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"
        )
    }

    private func shouldRetryArtwork() -> Bool {
        guard let lastArtworkAttemptDate else { return true }
        return Date().timeIntervalSince(lastArtworkAttemptDate) >= 5
    }

    private func execute(arguments: [String]) -> ProcessExecutionResult {
        guard let executableURL else {
            return ProcessExecutionResult(
                stdout: Data(), stderr: Data(), exitCode: nil, duration: 0,
                timedOut: false, launchError: "Bridge executable not found."
            )
        }
        return runner.run(
            executableURL: executableURL,
            arguments: arguments,
            timeout: timeout
        )
    }

    private static func parseRawJSON(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func normalizedValue(_ value: String) -> String {
        value == "null" ? "" : value
    }

    private static func hasValue(_ dictionary: [String: Any]?, _ key: String) -> Bool {
        guard let value = dictionary?[key] else { return false }
        if let string = value as? String { return !string.isEmpty }
        return true
    }

    private static func string(_ dictionary: [String: Any], _ key: String) -> String {
        dictionary[key] as? String ?? ""
    }

    private func image(fromBase64 base64: String) -> NSImage? {
        guard
            !base64.isEmpty,
            let data = Data(base64Encoded: base64),
            let source = CIImage(data: data)
        else { return nil }

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
        else { return NSImage(data: data) }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: source.extent.width, height: source.extent.height)
        )
    }
}
