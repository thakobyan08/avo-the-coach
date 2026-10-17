import AppKit
import Observation
import SwiftUI
import os

/// A floating panel that never becomes key, so the app you are typing in keeps keyboard focus.
final class NudgePanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // SwiftUI draws the card's own shadow.
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that takes the first click (the panel is never key) and reports hover even while Avo is
/// not the active app.
final class NudgeHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: (Bool) -> Void = { _ in }
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange(false)
    }
}

@Observable
final class PanelState {
    var isHovering = false
}

/// Shows the nudge panel at the top right of the screen you are working on, and slides it in and out
/// as the scheduler's phase changes.
final class NudgePanelController {
    private let model: AppModel
    private let panel = NudgePanel()
    private let state = PanelState()
    private var hostingView: NudgeHostingView<NudgeRoot>?
    private var isShown = false
    private var contentSize: CGSize = .zero
    private var screen: NSScreen?
    /// Bumped on every show and hide so a finished hide animation cannot order out a newer show.
    private var generation = 0
    private let log = Logger(subsystem: "com.thakobyan08.avo", category: "panel")

    init(model: AppModel) {
        self.model = model
        let root = NudgeRoot(model: model, state: state) { [weak self] size in
            self?.contentSizeChanged(size)
        }
        let hostingView = NudgeHostingView(rootView: root)
        hostingView.sizingOptions = []
        hostingView.onHoverChange = { [weak self] hovering in
            self?.hoverChanged(hovering)
        }
        panel.contentView = hostingView
        self.hostingView = hostingView
        observePhase()
    }

    private func observePhase() {
        withObservationTracking {
            _ = model.nudges.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.phaseChanged()
                self?.observePhase()
            }
        }
    }

    private func phaseChanged() {
        if model.nudges.phase == .hidden {
            hide()
        } else if !isShown {
            show()
        }
    }

    private func hoverChanged(_ hovering: Bool) {
        state.isHovering = hovering
        model.nudges.isHovering = hovering
        // Leaving the card restarts its 60 seconds.
        if !hovering, case .card = model.nudges.phase {
            model.nudges.keepCard()
        }
    }

    // MARK: Showing and hiding

    private func show() {
        screen = NSScreen.main ?? NSScreen.screens.first
        hostingView?.layoutSubtreeIfNeeded()
        let fitting = hostingView?.fittingSize ?? .zero
        let size = fitting.width > 0 ? fitting : contentSize
        // No size yet: `contentSizeChanged` calls back here once SwiftUI has laid the card out.
        guard size.width > 0 else { return }

        generation += 1
        isShown = true
        state.isHovering = false
        model.nudges.isHovering = false
        let target = targetFrame(for: size)
        log.debug("show fitting=\(fitting.debugDescription, privacy: .public) target=\(target.debugDescription, privacy: .public)")

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? target : target.offsetBy(dx: 48, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.2 : 0.35
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
        // Animations don't advance while the display sleeps; make sure the card ends up fully shown.
        let showing = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard let self, self.generation == showing, self.isShown else { return }
            self.panel.alphaValue = 1
            self.panel.setFrame(self.targetFrame(for: self.contentSize.width > 0 ? self.contentSize : target.size), display: true)
        }
    }

    private func hide() {
        guard isShown else { return }
        generation += 1
        let hiding = generation
        isShown = false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let frame = panel.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            if !reduceMotion { panel.animator().setFrame(frame.offsetBy(dx: 32, dy: 0), display: true) }
            panel.animator().alphaValue = 0
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.25))
            guard let self, self.generation == hiding else { return }
            self.panel.orderOut(nil)
        }
    }

    private func contentSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        log.debug("content size \(size.debugDescription, privacy: .public) shown=\(self.isShown)")
        guard isShown else {
            if model.nudges.phase != .hidden { show() }
            return
        }
        let target = targetFrame(for: size)
        guard target != panel.frame else { return }
        if size.width >= panel.frame.width && size.height >= panel.frame.height {
            // Growing: resize at once so nothing is clipped while SwiftUI animates the content.
            panel.setFrame(target, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        }
    }

    /// The panel's top-right corner sits at the top right of the visible screen area. The SwiftUI
    /// content carries its own margins and room for the shadow.
    private func targetFrame(for size: CGSize) -> NSRect {
        let visible = (screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSRect(
            x: visible.maxX - size.width,
            y: visible.maxY - size.height,
            width: size.width,
            height: size.height
        ).integral
    }
}

/// The panel's SwiftUI root: the content pinned to the top right, measured for the controller.
struct NudgeRoot: View {
    let model: AppModel
    let state: PanelState
    let onSize: (CGSize) -> Void

    var body: some View {
        NudgeContent(model: model, state: state)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .environment(\.colorScheme, .light)
    }
}
