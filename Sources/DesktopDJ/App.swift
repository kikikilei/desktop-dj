import AppKit
import SwiftUI

@main
struct DesktopDJApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject,
    NSApplicationDelegate,
    NSWindowDelegate,
    NSMenuDelegate
{
    private var panel: PetPanel?
    private var positionSaveWorkItem: DispatchWorkItem?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var isPreparingDiagnosticReport = false
    private var diagnosticReportCopiedAt: Date?
    private let player = PlayerViewModel()
    private let diagnosticService = NowPlayingService()
    private let expandedSize = NSSize(width: 230, height: 213)
    private let compactSize = NSSize(width: 80, height: 88)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        createPanel()
        createStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        positionSaveWorkItem?.cancel()
        rememberPosition()
    }

    func windowDidMove(_ notification: Notification) {
        positionSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.rememberPosition()
        }
        positionSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func createPanel() {
        let size = player.isCompact ? compactSize : expandedSize
        let panel = PetPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.delegate = self
        panel.menuProvider = { [weak self] in
            self?.makeContextMenu() ?? NSMenu()
        }
        panel.doubleClickHandler = { [weak self] in
            self?.toggleCompactMode()
        }
        panel.shouldHandleDoubleClick = { [weak self] point in
            guard let self else { return false }
            return self.player.isPetInteractionPoint(point)
        }
        panel.contentView = InteractiveHostingView(rootView: PetView(player: player))
        panel.setFrameOrigin(restoredOrigin(for: size))
        panel.orderFrontRegardless()

        self.panel = panel
    }

    private func resizePanel(isCompact: Bool) {
        guard let panel else { return }
        let size = isCompact ? compactSize : expandedSize
        let oldFrame = panel.frame
        var origin = NSPoint(
            x: oldFrame.midX - size.width / 2,
            y: oldFrame.midY - size.height / 2
        )

        if let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            origin.x = min(
                max(origin.x, visibleFrame.minX),
                visibleFrame.maxX - size.width
            )
            origin.y = min(
                max(origin.y, visibleFrame.minY),
                visibleFrame.maxY - size.height
            )
        }

        panel.setFrame(
            NSRect(origin: origin, size: size),
            display: true,
            animate: false
        )
        rememberPosition()
    }

    private func toggleCompactMode() {
        guard panel != nil else { return }

        player.setCompactMode(!player.isCompact)
        resizePanel(isCompact: player.isCompact)

        // Recreate the hosting surface for the destination mode. This prevents
        // AppKit from stretching the previous mode's last rendered frame into
        // the new panel size for one display refresh.
        refreshHostedContent()
    }

    private func refreshHostedContent() {
        guard let panel else { return }
        panel.contentView = InteractiveHostingView(
            rootView: PetView(player: player)
        )
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
    }

    private func restoredOrigin(for size: NSSize) -> NSPoint {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "desktopDJPetX") != nil,
           defaults.object(forKey: "desktopDJPetY") != nil {
            return NSPoint(
                x: defaults.double(forKey: "desktopDJPetX"),
                y: defaults.double(forKey: "desktopDJPetY")
            )
        }

        return defaultOrigin(for: size)
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: 40, y: 40)
        }

        return NSPoint(
            x: screen.visibleFrame.maxX - size.width - 28,
            y: screen.visibleFrame.minY + 34
        )
    }

    private func rememberPosition() {
        guard let origin = panel?.frame.origin else { return }
        UserDefaults.standard.set(origin.x, forKey: "desktopDJPetX")
        UserDefaults.standard.set(origin.y, forKey: "desktopDJPetY")
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        if let button = item.button {
            let image = AssetLoader.image(named: "logo-head")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = false
            button.image = image
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Desktop DJ"
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        statusMenu = menu
        rebuild(menu: menu, includeVisibility: true)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        rebuild(menu: menu, includeVisibility: true)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        rebuild(menu: menu, includeVisibility: false)
        return menu
    }

    private func rebuild(
        menu: NSMenu,
        includeVisibility: Bool
    ) {
        menu.removeAllItems()

        let nowPlaying = NSMenuItem(
            title: "\(player.title) — \(player.artist)",
            action: nil,
            keyEquivalent: ""
        )
        nowPlaying.isEnabled = false
        menu.addItem(nowPlaying)
        menu.addItem(.separator())

        if includeVisibility {
            menu.addItem(
                item(
                    panel?.isVisible == true
                        ? "Hide Desktop DJ"
                        : "Show Desktop DJ",
                    action: #selector(toggleVisibility)
                )
            )
        }

        menu.addItem(item("Previous · F7", action: #selector(previousTrack)))
        menu.addItem(
            item(
                player.isPlaying ? "Pause · F8" : "Play · F8",
                action: #selector(togglePlayPause)
            )
        )
        menu.addItem(item("Next · F9", action: #selector(nextTrack)))
        menu.addItem(.separator())
        menu.addItem(
            item(
                player.isCompact ? "Expand DJ Cat" : "Collapse to Headphones",
                action: #selector(toggleCompactModeFromMenu)
            )
        )

        let skinItem = NSMenuItem(
            title: "Skin",
            action: nil,
            keyEquivalent: ""
        )
        let skinMenu = NSMenu()
        for skin in player.availableSkins {
            let skinChoice = item(
                skin.definition.name,
                action: #selector(selectSkinFromMenu(_:))
            )
            skinChoice.representedObject = skin.id
            skinChoice.state = skin.id == player.activeSkinID ? .on : .off
            skinMenu.addItem(skinChoice)
        }
        skinMenu.addItem(.separator())
        skinMenu.addItem(
            item("Reload Skins", action: #selector(reloadSkins))
        )
        skinMenu.addItem(
            item("Open Skins Folder", action: #selector(openSkinsFolder))
        )
        menu.addItem(skinItem)
        menu.setSubmenu(skinMenu, for: skinItem)

        if includeVisibility {
            menu.addItem(
                item("Reset Position", action: #selector(resetPosition))
            )
        }

        menu.addItem(.separator())
        let diagnosticTitle: String
        if isPreparingDiagnosticReport {
            diagnosticTitle = "Preparing Diagnostic Report…"
        } else if let copiedAt = diagnosticReportCopiedAt,
                  Date().timeIntervalSince(copiedAt) < 4 {
            diagnosticTitle = "Copy Diagnostic Report ✓"
        } else {
            diagnosticTitle = "Copy Diagnostic Report"
        }
        let diagnosticItem = item(
            diagnosticTitle,
            action: #selector(copyDiagnosticReport)
        )
        diagnosticItem.isEnabled = !isPreparingDiagnosticReport
        menu.addItem(diagnosticItem)
        menu.addItem(.separator())
        menu.addItem(item("Quit Desktop DJ", action: #selector(quitDesktopDJ)))
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func previousTrack() { player.previous() }
    @objc private func togglePlayPause() { player.togglePlayPause() }
    @objc private func nextTrack() { player.next() }
    @objc private func toggleCompactModeFromMenu() { toggleCompactMode() }
    @objc private func toggleVisibility() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }
    @objc private func resetPosition() {
        guard let panel else { return }
        panel.setFrameOrigin(defaultOrigin(for: panel.frame.size))
        panel.orderFrontRegardless()
        rememberPosition()
    }
    @objc private func selectSkinFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        player.selectSkin(id: id)
        refreshHostedContent()
    }
    @objc private func reloadSkins() {
        player.reloadExternalSkins()
        refreshHostedContent()
    }
    @objc private func openSkinsFolder() {
        NSWorkspace.shared.open(player.skinsFolderURL)
    }
    @objc private func copyDiagnosticReport() {
        guard !isPreparingDiagnosticReport else { return }
        isPreparingDiagnosticReport = true

        let bundle = Bundle.main
        let bundleIdentifier = bundle.bundleIdentifier
        let runningInstances = bundleIdentifier.map {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: $0
            ).count
        } ?? 1
        let appContext = DiagnosticAppContext(
            version: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "Unknown",
            build: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "Unknown",
            mode: player.isPreviewMode ? "Preview" : "Live Now Playing",
            skin: player.activeSkin.definition.name,
            displayMode: player.isCompact ? "Compact" : "Expanded",
            appLocation: DiagnosticReportFormatter.safeAppLocation(
                bundle.bundleURL
            ),
            duplicateProcessCount: max(1, runningInstances),
            lastSuccessfulUpdateAge: player.lastSuccessfulUpdateAge
        )
        let service = diagnosticService

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let bridge = service.diagnose()
            let report = DiagnosticReportFormatter.make(
                app: appContext,
                bridge: bridge
            )
            DispatchQueue.main.async {
                guard let self else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(report, forType: .string)
                self.isPreparingDiagnosticReport = false
                self.diagnosticReportCopiedAt = Date()
                self.statusItem?.button?.toolTip =
                    "Desktop DJ — diagnostic report copied"

                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    [weak self] in
                    guard let self else { return }
                    self.diagnosticReportCopiedAt = nil
                    self.statusItem?.button?.toolTip = "Desktop DJ"
                }
            }
        }
    }
    @objc private func quitDesktopDJ() { NSApplication.shared.terminate(nil) }
}

final class PetPanel: NSPanel {
    var menuProvider: (() -> NSMenu)?
    var doubleClickHandler: (() -> Void)?
    var shouldHandleDoubleClick: ((NSPoint) -> Bool)?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown where event.clickCount == 2:
            let point = event.locationInWindow
            if shouldHandleDoubleClick?(point) == true {
                doubleClickHandler?()
                return
            }
            super.sendEvent(event)

        case .leftMouseDown:
            if shouldHandleDoubleClick?(event.locationInWindow) == true {
                dragStartMouseLocation = NSEvent.mouseLocation
                dragStartWindowOrigin = frame.origin
            }
            super.sendEvent(event)

        case .leftMouseDragged:
            guard
                let startMouseLocation = dragStartMouseLocation,
                let startWindowOrigin = dragStartWindowOrigin
            else {
                super.sendEvent(event)
                return
            }

            let currentMouseLocation = NSEvent.mouseLocation
            let screenDelta = NSPoint(
                x: currentMouseLocation.x - startMouseLocation.x,
                y: currentMouseLocation.y - startMouseLocation.y
            )

            if abs(screenDelta.x) + abs(screenDelta.y) > 0.5 {
                setFrameOrigin(
                    NSPoint(
                        x: startWindowOrigin.x + screenDelta.x,
                        y: startWindowOrigin.y + screenDelta.y
                    )
                )
            } else if abs(event.deltaX) + abs(event.deltaY) > 0 {
                setFrameOrigin(
                    NSPoint(
                        x: frame.origin.x + event.deltaX,
                        y: frame.origin.y - event.deltaY
                    )
                )
            }
            return

        case .leftMouseUp:
            dragStartMouseLocation = nil
            dragStartWindowOrigin = nil
            super.sendEvent(event)

        case .rightMouseDown:
            guard let menu = menuProvider?(), let contentView else {
                super.sendEvent(event)
                return
            }
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
            return

        default:
            super.sendEvent(event)
        }
    }
}

final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
