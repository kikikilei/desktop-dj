import AppKit
import Combine
import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var title = "Nothing playing"
    @Published private(set) var artist = "The cat is sleeping"
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var catState: CatState = .sleeping
    @Published private(set) var catAnimationGeneration = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var sourceBundleIdentifier = ""
    @Published private(set) var isPreviewMode = false
    @Published private(set) var isCompact = false
    @Published private(set) var activeSkinID: String
    @Published private(set) var currentAnimationURL: URL?

    private let service = NowPlayingService()
    private let skinCatalog: SkinCatalog
    private let animationScheduler: PlaybackAnimationScheduler
    private var pollTimer: Timer?
    private var progressTimer: Timer?
    private var identity = ""
    private var anchorElapsed: TimeInterval = 0
    private var anchorDate = Date()
    private var lastValidSnapshotDate: Date?
    private var isPolling = false
    private var switchGeneration = 0
    private var forcePlayingUntil: Date?
    private var pendingExternalPauseSince: Date?
    private var switchingAnimationDuration: TimeInterval {
        animationScheduler.duration(for: .switching) ?? 4.04
    }

    var availableSkins: [LoadedSkin] {
        skinCatalog.skins
    }

    var activeSkin: LoadedSkin {
        skinCatalog.current
    }

    var skinsFolderURL: URL {
        skinCatalog.externalSkinsURL
    }

    var displayedElapsed: TimeInterval {
        guard duration > 0 else { return 0 }
        let additional = isPlaying ? Date().timeIntervalSince(anchorDate) : 0
        return min(duration, max(0, anchorElapsed + additional))
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, displayedElapsed / duration)
    }

    var lastSuccessfulUpdateAge: TimeInterval? {
        lastValidSnapshotDate.map { Date().timeIntervalSince($0) }
    }

    init() {
        let catalog = SkinCatalog()
        skinCatalog = catalog
        animationScheduler = PlaybackAnimationScheduler(skin: catalog.current)
        activeSkinID = catalog.current.id
        artwork = AssetLoader.image(named: "logo-head")

        animationScheduler.onClipChange = { [weak self] _, url, restart in
            guard let self else { return }
            let didChangeFile = self.currentAnimationURL != url
            self.currentAnimationURL = url
            if restart || didChangeFile {
                self.catAnimationGeneration += 1
            }
        }
        animationScheduler.enter(state: .sleeping)
        refreshLiveSnapshot()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.refreshLiveSnapshot()
            }
        }

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }
    }

    func showPreview(_ scenario: PreviewScenario) {
        isPreviewMode = true
        forcePlayingUntil = nil
        pendingExternalPauseSince = nil
        sourceBundleIdentifier = "preview"
        identity = ""
        anchorDate = Date()
        artwork = AssetLoader.image(named: "logo-head")

        switch scenario {
        case .playing:
            title = "Night Drive"
            artist = "8BIT CITY"
            duration = 214
            anchorElapsed = 48
            isPlaying = true
            setCatState(.playing)

        case .sleeping:
            title = "Night Drive"
            artist = "8BIT CITY"
            duration = 214
            anchorElapsed = 48
            isPlaying = false
            setCatState(.sleeping)

        case .switching:
            title = "Changing track…"
            artist = "PREVIEW"
            duration = 214
            anchorElapsed = 0
            isPlaying = true
            setCatState(.switching)

        case .longTitle:
            title = "A Very Long Midnight Engineering Session"
            artist = "DESKTOP DJ LAB"
            duration = 383
            anchorElapsed = 162
            isPlaying = true
            setCatState(.playing)

        case .noArtwork:
            title = "Untitled Demo"
            artist = "LOCAL FILE"
            duration = 91
            anchorElapsed = 17
            artwork = nil
            isPlaying = true
            setCatState(.playing)

        case .lateProgress:
            title = "Silver Circuit"
            artist = "COW CAT"
            duration = 247
            anchorElapsed = 201
            isPlaying = true
            setCatState(.playing)
        }
    }

    func useLivePlayback() {
        isPreviewMode = false
        forcePlayingUntil = nil
        pendingExternalPauseSince = nil
        lastValidSnapshotDate = nil
        refreshLiveSnapshot()
    }

    func setCompactMode(_ compact: Bool) {
        isCompact = compact
    }

    func selectSkin(id: String) {
        guard skinCatalog.select(id: id) else { return }
        activeSkinID = skinCatalog.current.id
        animationScheduler.setSkin(skinCatalog.current)
        objectWillChange.send()
    }

    func reloadExternalSkins() {
        skinCatalog.reloadExternalSkins()
        if !skinCatalog.skins.contains(where: { $0.id == activeSkinID }) {
            activeSkinID = skinCatalog.current.id
            animationScheduler.setSkin(skinCatalog.current)
        }
        objectWillChange.send()
    }

    func compactImage(isPlaying: Bool) -> NSImage? {
        let path = isPlaying
            ? activeSkin.definition.compact.playing
            : activeSkin.definition.compact.paused
        return activeSkin.image(for: path)
    }

    func isPetInteractionPoint(_ point: NSPoint) -> Bool {
        let interaction = activeSkin.definition.interaction
        return isCompact
            ? interaction.compactPet.contains(point)
            : interaction.expandedPet.contains(point)
    }

    func togglePlayPause() {
        let nextPlaying = !isPlaying
        forcePlayingUntil = nil
        pendingExternalPauseSince = nil
        preserveProgressAndSetPlaying(nextPlaying)
        setCatState(nextPlaying ? .playing : .sleeping)

        guard !isPreviewMode else { return }
        send(.togglePlayPause)
        refreshAfter(0.08)
        refreshAfter(0.28)
    }

    func previous() {
        guard !isPreviewMode else {
            previewTrackChange(title: "Neon Compiler", artist: "8BIT CITY")
            return
        }
        showSwitchingState()
        send(.previous)
        refreshAfter(0.12)
    }

    func next() {
        guard !isPreviewMode else {
            previewTrackChange(title: "Silver Circuit", artist: "COW CAT")
            return
        }
        showSwitchingState()
        send(.next)
        refreshAfter(0.12)
    }

    private func refreshLiveSnapshot() {
        guard !isPreviewMode, !isPolling else { return }
        isPolling = true
        let service = service

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let snapshot = service.readSnapshot()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPolling = false
                self.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: NowPlayingSnapshot?) {
        guard let snapshot else {
            if let forcePlayingUntil, Date() < forcePlayingUntil {
                return
            }
            if let lastValidSnapshotDate,
               Date().timeIntervalSince(lastValidSnapshotDate) < 4 {
                return
            }
            setSleeping()
            return
        }

        lastValidSnapshotDate = Date()
        let estimatedElapsed = displayedElapsed
        let wasPlaying = isPlaying
        let didChangeTrack = !identity.isEmpty && identity != snapshot.identity
        let isInsideSwitchGrace = forcePlayingUntil.map { Date() < $0 } ?? false
        var effectivePlaying = snapshot.isPlaying || isInsideSwitchGrace

        if !snapshot.isPlaying, isPlaying, !isInsideSwitchGrace {
            if pendingExternalPauseSince == nil {
                pendingExternalPauseSince = Date()
            }
            if let pendingExternalPauseSince,
               Date().timeIntervalSince(pendingExternalPauseSince) < 0.65 {
                effectivePlaying = true
            }
        } else {
            pendingExternalPauseSince = nil
        }

        title = snapshot.title
        artist = snapshot.artist
        sourceBundleIdentifier = snapshot.sourceBundleIdentifier

        if identity != snapshot.identity {
            identity = snapshot.identity
            artwork = snapshot.artwork
            duration = max(0, snapshot.duration)
            anchorElapsed = snapshot.elapsed > 0 ? snapshot.elapsed : 0
            anchorDate = Date()
            if didChangeTrack {
                pendingExternalPauseSince = nil
                // A Previous/Next command already started the one-shot
                // switching animation. Do not restart it when the provider
                // catches up and reports the new metadata.
                if !isInsideSwitchGrace {
                    showSwitchingState()
                }
                effectivePlaying = true
            }
        } else {
            // Keep the last valid duration when NetEase temporarily reports
            // zero during a pause/resume transition.
            if snapshot.duration > 0 {
                duration = snapshot.duration
            }

            if snapshot.elapsed > 0 {
                let difference = snapshot.elapsed - estimatedElapsed
                if difference > 8 {
                    // A large forward jump is probably a real seek.
                    anchorElapsed = snapshot.elapsed
                    anchorDate = Date()
                } else if difference >= 0 {
                    // Never move backward within the same track. NetEase can
                    // return stale elapsed samples for several seconds after
                    // pause/resume.
                    anchorElapsed = max(estimatedElapsed, snapshot.elapsed)
                    anchorDate = Date()
                }
            }
        }

        if snapshot.isPlaying {
            pendingExternalPauseSince = nil
        }

        if wasPlaying != effectivePlaying {
            preserveProgressAndSetPlaying(effectivePlaying)
        } else {
            isPlaying = effectivePlaying
        }

        let desiredState: CatState = effectivePlaying ? .playing : .sleeping
        if catState != .switching, catState != desiredState {
            setCatState(desiredState)
        }
    }

    private func preserveProgressAndSetPlaying(_ playing: Bool) {
        anchorElapsed = displayedElapsed
        anchorDate = Date()
        isPlaying = playing
    }

    private func setSleeping() {
        title = "Nothing playing"
        artist = "The cat is sleeping"
        duration = 0
        anchorElapsed = 0
        isPlaying = false
        artwork = nil
        identity = ""
        setCatState(.sleeping)
    }

    private func previewTrackChange(title: String, artist: String) {
        showSwitchingState()
        DispatchQueue.main.asyncAfter(
            deadline: .now() + switchingAnimationDuration
        ) { [weak self] in
            guard let self, self.isPreviewMode else { return }
            self.title = title
            self.artist = artist
            self.duration = 247
            self.anchorElapsed = 0
            self.anchorDate = Date()
            self.isPlaying = true
        }
    }

    private func showSwitchingState() {
        switchGeneration += 1
        let generation = switchGeneration
        preserveProgressAndSetPlaying(true)
        forcePlayingUntil = Date().addingTimeInterval(
            switchingAnimationDuration + 0.4
        )
        pendingExternalPauseSince = nil
        setCatState(.switching)

        DispatchQueue.main.asyncAfter(
            deadline: .now() + switchingAnimationDuration
        ) { [weak self] in
            guard let self, generation == self.switchGeneration else { return }
            self.setCatState(.playing)
        }
    }

    private func setCatState(_ state: CatState) {
        catState = state
        let animationState: SkinAnimationState
        switch state {
        case .playing:
            animationState = .playing
        case .sleeping:
            animationState = .sleeping
        case .switching:
            animationState = .switching
        }
        animationScheduler.enter(state: animationState)
    }

    private func send(_ command: PlaybackCommand) {
        let service = service
        DispatchQueue.global(qos: .userInitiated).async {
            service.send(command)
        }
    }

    private func refreshAfter(_ delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refreshLiveSnapshot()
        }
    }
}
