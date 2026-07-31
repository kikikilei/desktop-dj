import AppKit
import SwiftUI

struct LoopingGIFView: NSViewRepresentable {
    let fileURL: URL?

    func makeNSView(context: Context) -> AnimatedGIFImageView {
        let imageView = AnimatedGIFImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.animates = true
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        imageView.setContentCompressionResistancePriority(
            .defaultLow,
            for: .vertical
        )
        imageView.loadedPath = fileURL?.path
        imageView.image = fileURL.flatMap(NSImage.init(contentsOf:))
        return imageView
    }

    func updateNSView(
        _ nsView: AnimatedGIFImageView,
        context: Context
    ) {
        let nextPath = fileURL?.path
        guard nsView.loadedPath != nextPath else { return }
        nsView.loadedPath = nextPath
        nsView.image = fileURL.flatMap(NSImage.init(contentsOf:))
        nsView.animates = true
    }
}

final class AnimatedGIFImageView: NSImageView {
    var loadedPath: String?

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: NSView.noIntrinsicMetric
        )
    }
}
