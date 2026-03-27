import SwiftUI
import AppKit

/// Transparent NSView that installs a local NSEvent monitor for F4.
/// Attach via `.background(F4KeyMonitor { ... })`.
struct F4KeyMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> _MonitorView {
        let v = _MonitorView()
        v.action = action
        return v
    }
    func updateNSView(_ v: _MonitorView, context: Context) {
        v.action = action
    }

    final class _MonitorView: NSView {
        var action: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    // F4 = key code 118
                    if event.keyCode == 118 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                        self?.action?()
                        return nil  // consume the event
                    }
                    return event
                }
            } else {
                if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            }
        }

        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }
    }
}
