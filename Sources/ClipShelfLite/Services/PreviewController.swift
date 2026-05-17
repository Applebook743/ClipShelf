import AppKit
import Foundation
import QuickLookUI

final class PreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = PreviewController()

    private var previewURLs: [URL] = []
    private var temporaryURLs: [URL] = []
    private var previewWindow: NSWindow?
    private var keyMonitor: Any?

    func togglePreview(_ items: [ClipItem]) {
        if closeIfVisible() {
            return
        }

        preview(items)
    }

    func preview(_ items: [ClipItem]) {
        if showBuiltInPreviewIfPossible(items) {
            return
        }

        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
        previewWindow?.orderOut(nil)

        cleanupTemporaryFiles()
        previewURLs = items.compactMap(previewURL(for:))

        guard !previewURLs.isEmpty, let panel = QLPreviewPanel.shared() else {
            return
        }

        panel.currentPreviewItemIndex = 0
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(self)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURLs[index] as NSURL
    }

    private func previewURL(for item: ClipItem) -> URL? {
        switch item.kind {
        case .file:
            return item.filePaths.first.map { URL(fileURLWithPath: $0) }
        case .image:
            if let sourcePath = item.sourcePath, FileManager.default.fileExists(atPath: sourcePath) {
                return URL(fileURLWithPath: sourcePath)
            }

            guard let imageData = item.imageData else { return nil }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClipShelfPreview-\(item.id.uuidString).png")
            try? imageData.write(to: url, options: .atomic)
            temporaryURLs.append(url)
            return url
        case .text:
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ClipShelfPreview-\(item.id.uuidString).txt")
            try? (item.text ?? item.title).write(to: url, atomically: true, encoding: .utf8)
            temporaryURLs.append(url)
            return url
        }
    }

    @discardableResult
    func closeIfVisible() -> Bool {
        var didClose = false

        if let window = previewWindow, window.isVisible {
            window.orderOut(nil)
            didClose = true
        }

        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
            didClose = true
        }

        if didClose {
            stopKeyMonitor()
        }

        return didClose
    }

    private func showBuiltInPreviewIfPossible(_ items: [ClipItem]) -> Bool {
        guard items.count == 1, let item = items.first else {
            return false
        }

        switch item.kind {
        case .image:
            if let image = image(for: item) {
                showImagePreview(image, title: item.title)
                return true
            }
            return false
        case .text:
            showTextPreview(item.text ?? item.title, title: item.title)
            return true
        case .file:
            guard item.filePaths.count == 1 else { return false }
            let url = URL(fileURLWithPath: item.filePaths[0])
            if let image = NSImage(contentsOf: url) {
                showImagePreview(image, title: url.lastPathComponent)
                return true
            }
            return false
        }
    }

    private func image(for item: ClipItem) -> NSImage? {
        if let imageData = item.imageData, let image = NSImage(data: imageData) {
            return image
        }

        if let sourcePath = item.sourcePath {
            return NSImage(contentsOf: URL(fileURLWithPath: sourcePath))
        }

        return nil
    }

    private func showImagePreview(_ image: NSImage, title: String) {
        let panel = previewPanel(title: title, size: NSSize(width: 760, height: 560))
        let scrollView = NSScrollView(frame: panel.contentView?.bounds ?? .zero)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.frame = scrollView.contentView.bounds
        imageView.autoresizingMask = [.width, .height]

        scrollView.documentView = imageView
        panel.contentView = scrollView
        show(panel)
    }

    private func showTextPreview(_ text: String, title: String) {
        let panel = previewPanel(title: title, size: NSSize(width: 640, height: 460))
        let scrollView = NSScrollView(frame: panel.contentView?.bounds ?? .zero)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.font = .systemFont(ofSize: 15)
        textView.string = text
        textView.textContainerInset = NSSize(width: 18, height: 18)

        scrollView.documentView = textView
        panel.contentView = scrollView
        show(panel)
    }

    private func previewPanel(title: String, size: NSSize) -> NSPanel {
        previewWindow?.orderOut(nil)

        let panel = SpaceClosablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.onSpace = { [weak self] in
            self?.closeIfVisible()
        }
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.center()
        previewWindow = panel
        return panel
    }

    private func show(_ panel: NSWindow) {
        startKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 49,
                  let self,
                  self.previewWindow?.isVisible == true || QLPreviewPanel.shared()?.isVisible == true else {
                return event
            }

            self.closeIfVisible()
            return nil
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func cleanupTemporaryFiles() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }
}

private final class SpaceClosablePanel: NSPanel {
    var onSpace: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            onSpace?()
        } else {
            super.keyDown(with: event)
        }
    }
}
