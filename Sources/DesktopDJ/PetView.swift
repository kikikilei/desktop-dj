import AppKit
import SwiftUI

struct PetView: View {
    @ObservedObject var player: PlayerViewModel
    @State private var hover = false

    var body: some View {
        Group {
            if player.isCompact {
                compactView
            } else {
                expandedView
            }
        }
        .frame(
            width: player.isCompact ? 80 : 270,
            height: player.isCompact ? 88 : 250,
            alignment: .topLeading
        )
        .scaleEffect(player.isCompact ? 1 : 0.85, anchor: .topLeading)
        .frame(
            width: player.isCompact ? 80 : 230,
            height: player.isCompact ? 88 : 213,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Desktop DJ music companion")
    }

    private var expandedView: some View {
        VStack(spacing: -10) {
            CatSprite(animationURL: player.currentAnimationURL)
                .id(player.catAnimationGeneration)
                .frame(width: 250, height: 184)
                .overlay {
                    NativePetInteractionLayer()
                }
                .playbackSway(
                    active: player.isPlaying && player.catState == .playing
                )

            PlayerStrip(player: player, hover: hover)
                .frame(width: 250, height: 64)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var compactView: some View {
        ZStack(alignment: .bottom) {
            Image(
                nsImage: player.compactImage(
                    isPlaying: player.isPlaying
                ) ?? NSImage()
            )
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: 78, height: 78)
            .overlay {
                NativePetInteractionLayer()
            }
            .playbackSway(
                active: player.isPlaying && player.catState == .playing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack(spacing: 2) {
                CompactControl(symbol: "backward.fill", action: player.previous)
                CompactControl(
                    symbol: player.isPlaying ? "pause.fill" : "play.fill",
                    action: player.togglePlayPause
                )
                CompactControl(symbol: "forward.fill", action: player.next)
            }
            .padding(.horizontal, 4)
            .frame(height: 22)
            .background(
                Capsule()
                    .fill(Color(red: 0.045, green: 0.047, blue: 0.06).opacity(0.94))
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
            .opacity(hover ? 1 : 0)
            .allowsHitTesting(hover)
        }
        .frame(width: 80, height: 88)
        .background {
            NativeHoverLayer(isHovering: $hover)
        }
    }
}

private extension View {
    func playbackSway(active: Bool) -> some View {
        modifier(GentlePlaybackSway(active: active))
    }
}

private struct GentlePlaybackSway: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 12.0, paused: !active)
        ) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let phase = seconds * 2 * Double.pi / 3.2
            let horizontal = active
                ? CGFloat((sin(phase) * 1.15).rounded())
                : 0
            let vertical = active
                ? CGFloat((sin(phase * 0.72 + 0.8) * 0.75).rounded())
                : 0

            content.offset(x: horizontal, y: vertical)
        }
    }
}

private struct NativePetInteractionLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> InteractionView {
        InteractionView()
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {}

    final class InteractionView: NSView {
        override var isOpaque: Bool { false }
        override var mouseDownCanMoveWindow: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

    }
}

private struct NativeHoverLayer: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        view.onHover = { value in
            DispatchQueue.main.async {
                isHovering = value
            }
        }
        return view
    }

    func updateNSView(_ nsView: HoverTrackingView, context: Context) {
        nsView.onHover = { value in
            DispatchQueue.main.async {
                isHovering = value
            }
        }
    }

    final class HoverTrackingView: NSView {
        var onHover: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [
                        .mouseEnteredAndExited,
                        .activeAlways,
                        .inVisibleRect
                    ],
                    owner: self
                )
            )
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

private struct CatSprite: View {
    let animationURL: URL?

    var body: some View {
        LoopingGIFView(fileURL: animationURL)
    }
}

private struct PlayerStrip: View {
    @ObservedObject var player: PlayerViewModel
    let hover: Bool

    var body: some View {
        HStack(spacing: 6) {
            CoverView(image: player.artwork)

            VStack(alignment: .leading, spacing: 4) {
                MarqueeTitle(text: player.title)

                Text(player.artist)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.tail)

                ProgressLine(
                    progress: player.progress,
                    elapsed: player.displayedElapsed,
                    duration: player.duration
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                if hover {
                    HStack(spacing: 3) {
                        MiniControl(symbol: "backward.fill", action: player.previous)
                        MiniControl(symbol: "forward.fill", action: player.next)
                    }
                    .transition(.opacity)
                }

                Button(action: player.togglePlayPause) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.09))
                        .overlay {
                            Rectangle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help(player.isPlaying ? "Pause (F8)" : "Play (F8)")
            }
            .frame(width: 34)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(red: 0.045, green: 0.047, blue: 0.06).opacity(0.96))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.38), radius: 10, y: 5)
        .animation(.easeOut(duration: 0.16), value: hover)
    }
}

private struct MarqueeTitle: View {
    let text: String
    @State private var startDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let label = Text(text)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                let resolved = context.resolve(label)
                let measured = resolved.measure(
                    in: CGSize(width: 10_000, height: size.height)
                )
                let overflow = max(0, measured.width - size.width)
                let pause: TimeInterval = 1.25
                let speed: CGFloat = 20
                let travel = overflow > 0 ? TimeInterval(overflow / speed) : 0
                let cycle = pause + travel + pause
                let elapsed = max(0, timeline.date.timeIntervalSince(startDate))
                let phase = cycle > 0 ? elapsed.truncatingRemainder(dividingBy: cycle) : 0

                let offset: CGFloat
                if overflow == 0 || phase < pause {
                    offset = 0
                } else if phase < pause + travel {
                    offset = min(overflow, CGFloat(phase - pause) * speed)
                } else {
                    offset = overflow
                }

                context.draw(
                    resolved,
                    at: CGPoint(x: -offset, y: size.height / 2),
                    anchor: .leading
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 13)
        .clipped()
        .accessibilityLabel(text)
        .onChange(of: text) { _ in
            startDate = Date()
        }
    }
}

private struct CoverView: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.06))
            }
        }
        .frame(width: 44, height: 44)
        .clipped()
        .overlay {
            Rectangle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct ProgressLine: View {
    let progress: Double
    let elapsed: TimeInterval
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 4) {
            Text(time(elapsed))
                .frame(width: 25, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.13))
                        .frame(height: 5)

                    Rectangle()
                        .fill(Color(red: 0.62, green: 0.34, blue: 1))
                        .frame(width: max(0, proxy.size.width * progress), height: 5)

                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .offset(x: max(0, proxy.size.width * progress - 3.5))
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 8)

            Text(time(duration))
                .frame(width: 25, alignment: .trailing)
        }
        .font(.system(size: 7, weight: .semibold, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.58))
    }

    private func time(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else { return "0:00" }
        let total = Int(interval.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct MiniControl: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: 18, height: 14)
        }
        .buttonStyle(.plain)
    }
}

private struct CompactControl: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }
}

enum AssetLoader {
    static func image(named name: String) -> NSImage? {
        let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("\(name).png")

        if let resourceURL, let image = NSImage(contentsOf: resourceURL) {
            return image
        }

        let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets")
            .appendingPathComponent("\(name).png")
        return NSImage(contentsOf: fallback)
    }
}
