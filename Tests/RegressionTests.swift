import Foundation

enum RegressionTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
enum RegressionTests {
    static func main() throws {
        try testLargeOutputDoesNotDeadlock()
        try testHungProcessTimesOut()
        try testStandardErrorIsCaptured()
        try testMetadataParsing()
        try testArtworkIsFetchedOnlyOncePerTrack()
        try testDiagnosticPrivacy()
        print("Regression tests passed")
    }

    private static func testLargeOutputDoesNotDeadlock() throws {
        let result = ProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "dd if=/dev/zero bs=1024 count=256 2>/dev/null"],
            timeout: 2
        )
        try require(!result.timedOut, "Large output timed out")
        try require(result.exitCode == 0, "Large-output process failed")
        try require(
            result.stdout.count == 256 * 1_024,
            "Large stdout was not fully drained"
        )
    }

    private static func testHungProcessTimesOut() throws {
        let result = ProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 5"],
            timeout: 0.1
        )
        try require(result.timedOut, "Hung process did not time out")
        try require(result.duration < 1.5, "Timeout took too long")
    }

    private static func testStandardErrorIsCaptured() throws {
        let result = ProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf problem >&2; exit 7"],
            timeout: 1
        )
        try require(result.exitCode == 7, "Exit status was lost")
        try require(
            String(data: result.stderr, encoding: .utf8) == "problem",
            "Standard error was not captured"
        )
    }

    private static func testMetadataParsing() throws {
        let data = Data("Song\nArtist\nAlbum\n240.5\n12.25\n1\n".utf8)
        guard let metadata = NowPlayingService.parseMetadataOutput(data) else {
            throw RegressionTestFailure.failed("Metadata did not parse")
        }
        try require(metadata.title == "Song", "Title parsed incorrectly")
        try require(metadata.artist == "Artist", "Artist parsed incorrectly")
        try require(metadata.duration == 240.5, "Duration parsed incorrectly")

        let missing = Data("null\nArtist\nnull\nnull\n0\n0\n".utf8)
        guard let normalized = NowPlayingService.parseMetadataOutput(missing) else {
            throw RegressionTestFailure.failed("Missing metadata did not parse")
        }
        try require(normalized.title.isEmpty, "Null title was not normalized")
        try require(normalized.album.isEmpty, "Null album was not normalized")
    }

    private static func testDiagnosticPrivacy() throws {
        let sanitized = DiagnosticReportFormatter.sanitize(
            "/Users/alice/Desktop/private\nsecond line"
        )
        try require(
            sanitized == "$HOME/Desktop/private second line",
            "Diagnostic path was not sanitized"
        )
        try require(!sanitized.contains("alice"), "User name leaked")
    }

    private static func testArtworkIsFetchedOnlyOncePerTrack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "desktop-dj-cache-test-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("fake-nowplaying")
        let counter = directory.appendingPathComponent("raw-count")
        let script = """
        #!/bin/sh
        if [ "$1" = "get" ]; then
          printf 'Song\\nArtist\\nAlbum\\n240\\n12\\n1\\n'
        else
          count=0
          if [ -f "\(counter.path)" ]; then count=$(cat "\(counter.path)"); fi
          count=$((count + 1))
          printf '%s' "$count" > "\(counter.path)"
          printf '{"kMRMediaRemoteNowPlayingInfoTitle":"Song","kMRMediaRemoteNowPlayingInfoArtist":"Artist","kMRMediaRemoteNowPlayingInfoClientBundleIdentifier":"test.player"}'
        fi
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let service = NowPlayingService(
            executableCandidates: [(executable, .embedded)],
            timeout: 1
        )
        _ = service.readSnapshot()
        _ = service.readSnapshot()

        let count = try String(contentsOf: counter, encoding: .utf8)
        try require(count == "1", "Artwork was fetched more than once for one track")
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        if !condition() {
            throw RegressionTestFailure.failed(message)
        }
    }
}
