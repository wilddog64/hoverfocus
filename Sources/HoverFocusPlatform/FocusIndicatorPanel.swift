import AppKit
import HoverFocusCore

private final class IndicatorStripPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class FocusIndicatorPanel {
    private var strips: [IndicatorStripPanel]?
    private var lastFrame: NSRect?
    private var isVisible = false

    init() {}

    private func createStrips() -> [IndicatorStripPanel] {
        if let strips { return strips }
        let created = (0..<4).map { _ in
            let panel = IndicatorStripPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .normal
            panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
            panel.backgroundColor = NSColor.controlAccentColor
            return panel
        }
        strips = created
        return created
    }

    func show(windowFrame: NSRect, aboveWindow id: UInt32) {
        guard id != 0 else {
            hide()
            return
        }
        let panels = createStrips()
        let frameChanged = lastFrame != windowFrame
        if frameChanged || !isVisible {
            let winRect = IndicatorRect(
                x: windowFrame.origin.x,
                y: windowFrame.origin.y,
                width: windowFrame.size.width,
                height: windowFrame.size.height
            )
            let rects = IndicatorGeometry.strips(around: winRect)
            for (panel, rect) in zip(panels, rects) {
                panel.setFrame(NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height), display: true)
            }
            lastFrame = windowFrame
            isVisible = true
        }
        for panel in panels {
            panel.order(.above, relativeTo: Int(id))
        }
    }

    func hide() {
        guard let strips, isVisible else { return }
        for panel in strips {
            panel.orderOut(nil)
        }
        isVisible = false
        lastFrame = nil
    }
}
