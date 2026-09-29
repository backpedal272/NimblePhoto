import AppKit
import SwiftUI

/// Quits the app when the window hosting this view closes, so auxiliary
/// windows (Settings, Welcome) left open don't keep NimblePhoto running
/// after the main window is dismissed.
struct WindowCloseTerminator: NSViewRepresentable {
    final class Coordinator {
        var observer: NSObjectProtocol?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window, context.coordinator.observer == nil else { return }
            context.coordinator.observer = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                NSApplication.shared.terminate(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
