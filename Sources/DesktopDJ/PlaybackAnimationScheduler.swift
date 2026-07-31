import Foundation

@MainActor
final class PlaybackAnimationScheduler {
    var onClipChange: ((SkinAnimationClip, URL, Bool) -> Void)?

    private var skin: LoadedSkin
    private var state: SkinAnimationState = .playing
    private var currentClip: SkinAnimationClip?
    private var cycleTimer: Timer?
    private var lastPlayedAt: [String: Date] = [:]

    init(skin: LoadedSkin) {
        self.skin = skin
    }

    func setSkin(_ skin: LoadedSkin) {
        self.skin = skin
        lastPlayedAt.removeAll()
        enter(state: state, restart: true)
    }

    func enter(state: SkinAnimationState, restart: Bool = true) {
        cycleTimer?.invalidate()
        cycleTimer = nil
        self.state = state

        guard let clip = primaryClip(for: state) else { return }
        setCurrent(clip, restart: restart)

        if state == .playing {
            scheduleBoundary(after: clip.duration)
        }
    }

    func stop() {
        cycleTimer?.invalidate()
        cycleTimer = nil
    }

    func duration(for state: SkinAnimationState) -> TimeInterval? {
        primaryClip(for: state)?.duration
    }

    private func primaryClip(
        for state: SkinAnimationState
    ) -> SkinAnimationClip? {
        let clips = skin.definition.clips(for: state)
        return clips.first(where: \.isPrimary) ?? clips.first
    }

    private func scheduleBoundary(after duration: TimeInterval) {
        cycleTimer?.invalidate()
        cycleTimer = Timer.scheduledTimer(
            withTimeInterval: max(0.1, duration),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.advancePlayingSequence()
            }
        }
    }

    private func advancePlayingSequence() {
        guard state == .playing, let currentClip else { return }

        let next: SkinAnimationClip
        if !currentClip.isPrimary {
            next = primaryClip(for: .playing) ?? currentClip
        } else {
            next = chooseWeightedPlayingClip() ?? currentClip
        }

        let didChange = next.id != currentClip.id
        setCurrent(next, restart: didChange)
        scheduleBoundary(after: next.duration)
    }

    private func chooseWeightedPlayingClip() -> SkinAnimationClip? {
        let now = Date()
        let eligible = skin.definition.clips(for: .playing).filter { clip in
            guard clip.weight > 0 else { return false }
            guard clip.cooldownSeconds > 0 else { return true }
            guard let lastPlayed = lastPlayedAt[clip.id] else { return true }
            return now.timeIntervalSince(lastPlayed) >= clip.cooldownSeconds
        }

        let totalWeight = eligible.reduce(0) {
            $0 + max(0, $1.weight)
        }
        guard totalWeight > 0 else {
            return primaryClip(for: .playing)
        }

        var cursor = Double.random(in: 0..<totalWeight)
        for clip in eligible {
            cursor -= max(0, clip.weight)
            if cursor <= 0 {
                return clip
            }
        }
        return eligible.last
    }

    private func setCurrent(
        _ clip: SkinAnimationClip,
        restart: Bool
    ) {
        currentClip = clip
        lastPlayedAt[clip.id] = Date()
        onClipChange?(clip, skin.url(for: clip.file), restart)
    }
}
