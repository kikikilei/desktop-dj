import Foundation

struct DiagnosticAppContext: Sendable {
    let version: String
    let build: String
    let mode: String
    let skin: String
    let displayMode: String
    let appLocation: String
    let duplicateProcessCount: Int
    let lastSuccessfulUpdateAge: TimeInterval?
}

enum DiagnosticReportFormatter {
    static func make(
        app: DiagnosticAppContext,
        bridge: BridgeDiagnostic,
        generatedAt: Date = Date()
    ) -> String {
        let source = bridge.sourceBundleIdentifier.isEmpty
            ? "Not available"
            : bridge.sourceBundleIdentifier
        let error = bridge.error.map(sanitize) ?? "None"

        return """
        Desktop DJ Diagnostic Report
        Generated: \(dateFormatter.string(from: generatedAt))

        App
        - Version: \(app.version) (\(app.build))
        - Mode: \(app.mode)
        - Skin: \(app.skin)
        - Display: \(app.displayMode)
        - Location: \(app.appLocation)
        - Running instances: \(app.duplicateProcessCount)

        System
        - macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - Architecture: \(architecture)

        Now Playing Bridge
        - Location: \(bridge.location.rawValue)
        - Found: \(yesNo(bridge.found))
        - Executable: \(yesNo(bridge.executable))
        - Exit code: \(bridge.exitCode.map(String.init) ?? "Not available")
        - Response time: \(String(format: "%.3fs", bridge.responseTime))
        - Response size: \(bridge.responseBytes) bytes
        - Timed out: \(yesNo(bridge.timedOut))
        - JSON valid: \(yesNo(bridge.jsonValid))
        - Error: \(error)

        Now Playing Result
        - Player detected: \(source)
        - Title available: \(yesNo(bridge.titleAvailable))
        - Artist available: \(yesNo(bridge.artistAvailable))
        - Playback rate available: \(yesNo(bridge.playbackRateAvailable))
        - Playback rate: \(bridge.playbackRate.map { String(format: "%.2f", $0) } ?? "Not available")
        - Duration available: \(yesNo(bridge.durationAvailable))
        - Artwork available: \(yesNo(bridge.artworkAvailable))
        - Last successful app update: \(updateAge(app.lastSuccessfulUpdateAge))

        Privacy
        - Song title, artist, album, artwork data, account details, and the user name in local paths were omitted.
        - No diagnostic data was uploaded automatically.
        """
    }

    static func safeAppLocation(_ url: URL) -> String {
        sanitize(url.path)
    }

    static func sanitize(_ text: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var result = text.replacingOccurrences(of: home, with: "$HOME")
        result = result.replacingOccurrences(
            of: #"/Users/[^/\s]+"#,
            with: "$HOME",
            options: .regularExpression
        )
        return String(
            result
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .prefix(400)
        )
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private static func updateAge(_ age: TimeInterval?) -> String {
        guard let age else { return "Never" }
        if age < 1 { return "Less than 1 second ago" }
        return "\(Int(age.rounded())) seconds ago"
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        return "x86_64 (Intel)"
        #else
        return "Unknown"
        #endif
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        return formatter
    }()
}
