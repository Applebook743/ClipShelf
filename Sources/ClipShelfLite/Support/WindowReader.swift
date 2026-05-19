import AppKit
import SwiftUI

struct WindowReader: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolveSoon(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolveSoon(from: nsView)
    }

    private func resolveSoon(from view: NSView) {
        DispatchQueue.main.async {
            onResolve(view.window)
        }
    }
}
