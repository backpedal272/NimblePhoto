import AppKit
import SwiftUI

/// Delivers two-finger scroll and smart-zoom (two-finger double-tap) events
/// that land inside this view's frame. SwiftUI has no modifier for raw
/// scroll deltas on a non-scrolling view, so this watches the window's
/// event stream instead of hit-testing: it never blocks clicks, drags, or
/// context menus on the content it sits behind.
struct TrackpadEventMonitor: NSViewRepresentable {
    /// Scroll delta in points, content-follows-fingers (respects the user's
    /// natural-scrolling setting). Return true to consume the event.
    var onScroll: (ScrollEvent) -> Bool
    /// Location in view coordinates, top-left origin.
    var onSmartMagnify: (CGPoint) -> Void

    struct ScrollEvent {
        let delta: CGSize
        /// Trackpad / Magic Mouse (pixel-precise) vs. a line-based wheel.
        let isPrecise: Bool
        let phase: NSEvent.Phase
        /// Inertial scrolling after the fingers lift.
        let isMomentum: Bool
    }

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.handlers = self
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.handlers = self
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class MonitorView: NSView {
        var handlers: TrackpadEventMonitor?
        private var monitor: Any?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .smartMagnify]) { [weak self] event in
                guard let self, let handlers = self.handlers,
                      event.window === self.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }

                switch event.type {
                case .smartMagnify:
                    handlers.onSmartMagnify(point)
                    return nil
                case .scrollWheel:
                    // Wheel mice report lines; scale to roughly match a trackpad.
                    let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
                    let scroll = ScrollEvent(
                        delta: CGSize(width: event.scrollingDeltaX * factor, height: event.scrollingDeltaY * factor),
                        isPrecise: event.hasPreciseScrollingDeltas,
                        phase: event.phase,
                        isMomentum: event.momentumPhase != []
                    )
                    return handlers.onScroll(scroll) ? nil : event
                default:
                    return event
                }
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
