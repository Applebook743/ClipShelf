import AppKit
import Foundation
import QuickLookUI

final class PreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = PreviewController()

    private var previewEntries: [PreviewEntry] = []
    private var temporaryURLs: [URL] = []
    private var previewWindow: NSWindow?
    private var keyMonitor: Any?
    private var onNavigate: ((Int) -> Bool)?

    func togglePreview(_ items: [ClipItem], onNavigate: ((Int) -> Bool)? = nil) {
        if closeIfVisible() {
            return
        }

        preview(items, onNavigate: onNavigate)
    }

    func preview(_ items: [ClipItem], onNavigate: ((Int) -> Bool)? = nil) {
        guard items.count == 1 else { return }

        self.onNavigate = onNavigate

        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
        previewWindow?.orderOut(nil)

        cleanupTemporaryFiles()

        if showBuiltInPreviewIfPossible(items) {
            return
        }

        previewEntries = items.compactMap(previewEntry(for:))

        guard !previewEntries.isEmpty, let panel = QLPreviewPanel.shared() else {
            return
        }

        panel.currentPreviewItemIndex = 0
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        applyFixedPreviewFrame(to: panel)
        startKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(self)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewEntries.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewEntries[index].url as NSURL
    }

    private func previewEntry(for item: ClipItem) -> PreviewEntry? {
        guard let url = previewURL(for: item) else { return nil }
        return PreviewEntry(
            url: url,
            recommendedSize: recommendedSize(for: item, url: url)
        )
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
            onNavigate = nil
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
        show(panel, firstResponder: scrollView)
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
        show(panel, firstResponder: textView)
    }

    private func recommendedSize(for item: ClipItem, url: URL) -> NSSize {
        switch item.kind {
        case .image:
            let image = image(for: item) ?? NSImage(contentsOf: url)
            return recommendedImageWindowSize(for: image?.size)
        case .text:
            return NSSize(width: 760, height: 560)
        case .file:
            return NSSize(width: 900, height: 700)
        }
    }

    private func recommendedImageWindowSize(for imageSize: NSSize?) -> NSSize {
        let minimum = NSSize(width: 520, height: 380)
        guard let imageSize,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return NSSize(width: 760, height: 560)
        }

        let maxSize = maximumPreviewWindowSize()
        let paddedSize = NSSize(
            width: imageSize.width + 96,
            height: imageSize.height + 120
        )
        let scale = min(
            maxSize.width / paddedSize.width,
            maxSize.height / paddedSize.height,
            1
        )

        return NSSize(
            width: min(max(paddedSize.width * scale, minimum.width), maxSize.width),
            height: min(max(paddedSize.height * scale, minimum.height), maxSize.height)
        )
    }

    private func maximumPreviewWindowSize() -> NSSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        return NSSize(
            width: max(520, visibleFrame.width * 0.9),
            height: max(380, visibleFrame.height * 0.9)
        )
    }

    private func constrainedPreviewSize(_ size: NSSize, for panel: NSWindow) -> NSSize {
        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let minimum = NSSize(width: 520, height: 380)
        let maximum = NSSize(width: visibleFrame.width * 0.92, height: visibleFrame.height * 0.92)

        return NSSize(
            width: min(max(size.width, minimum.width), maximum.width),
            height: min(max(size.height, minimum.height), maximum.height)
        )
    }

    private func applyFixedPreviewFrame(to panel: NSWindow) {
        let size = fixedPreviewWindowSize(for: panel)
        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = centeredFrame(for: size, in: visibleFrame)
        panel.setFrame(frame, display: true, animate: false)
    }

    private func fixedPreviewWindowSize(for panel: NSWindow) -> NSSize {
        let fallback = NSSize(width: 760, height: 560)
        let largestSize = previewEntries.reduce(fallback) { partial, entry in
            NSSize(
                width: max(partial.width, entry.recommendedSize.width),
                height: max(partial.height, entry.recommendedSize.height)
            )
        }

        return constrainedPreviewSize(largestSize, for: panel)
    }

    private func centeredFrame(for size: NSSize, in visibleFrame: NSRect) -> NSRect {
        let anchor = centerPoint(of: visibleFrame)
        var frame = NSRect(
            x: anchor.x - size.width / 2,
            y: anchor.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        if frame.minX < visibleFrame.minX {
            frame.origin.x = visibleFrame.minX
        }
        if frame.maxX > visibleFrame.maxX {
            frame.origin.x = visibleFrame.maxX - frame.width
        }
        if frame.minY < visibleFrame.minY {
            frame.origin.y = visibleFrame.minY
        }
        if frame.maxY > visibleFrame.maxY {
            frame.origin.y = visibleFrame.maxY - frame.height
        }

        return frame
    }

    private func centerPoint(of rect: NSRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
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

    private func show(_ panel: NSWindow, firstResponder: NSResponder? = nil) {
        startKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if let firstResponder {
            panel.makeFirstResponder(firstResponder)
        }
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isPreviewVisible else {
                return event
            }

            if event.keyCode == 49 {
                self.closeIfVisible()
                return nil
            }

            if let direction = self.previewNavigationDirection(for: event),
               self.onNavigate?(direction) == true {
                return nil
            }

            return event
        }
    }

    private var isPreviewVisible: Bool {
        previewWindow?.isVisible == true || QLPreviewPanel.shared()?.isVisible == true
    }

    private func previewNavigationDirection(for event: NSEvent) -> Int? {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return nil
        }

        if event.keyCode == 123 { return -1 }
        if event.keyCode == 124 { return 1 }

        return nil
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

private struct PreviewEntry {
    let url: URL
    let recommendedSize: NSSize
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
