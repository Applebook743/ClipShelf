import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var store: ClipStore
    @ObservedObject var watcher: ScreenshotFolderWatcher
    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var selectedIDs = Set<ClipItem.ID>()
    @State private var focusedID: ClipItem.ID?
    @State private var anchorID: ClipItem.ID?
    @State private var isDragSelecting = false
    @State private var dragAnchorID: ClipItem.ID?
    @State private var rowFrames: [ClipItem.ID: CGRect] = [:]
    @State private var historyViewportFrame: CGRect = .zero
    @State private var autoScrollTimer: Timer?
    @State private var autoScrollDirection = 0
    @State private var historyScrollView: NSScrollView?
    @State private var selectionColor = SelectionColorPreferences.color
    @State private var commandKeyMonitor: Any?
    @State private var appIconChoice = AppIconPreferences.selected
    @State private var clearSelectionHotKey = ClearSelectionHotKeyDefaults.load()
    @State private var pinHotKey = PinHotKeyDefaults.load()

    private var filteredItems: [ClipItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.items }

        return store.items.filter { SearchMatcher.matches($0, query: query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if filteredItems.isEmpty {
                emptyView
            } else {
                historyList
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .background(AppTheme.appBackground)
        .overlay {
            if showingSettings {
                settingsOverlay
            }
        }
        .onAppear {
            installCommandKeyMonitorIfNeeded()
        }
        .onDisappear {
            stopAutoScroll()
            removeCommandKeyMonitor()
        }
    }

    private var settingsOverlay: some View {
        GeometryReader { proxy in
            let panelWidth = min(max(proxy.size.width - 96, 560), 760)
            let panelHeight = max(proxy.size.height - 96, 360)

            ZStack {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingSettings = false
                    }

                SettingsView(store: store, watcher: watcher) {
                    showingSettings = false
                }
                .frame(width: panelWidth, height: panelHeight)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .contentShape(Rectangle())
                .onTapGesture { }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredItems) { item in
                        ClipRow(
                            item: item,
                            store: store,
                            isFocused: focusedID == item.id,
                            isSelected: selectedIDs.contains(item.id),
                            selectionColor: selectionColor,
                            handleClick: { event in handleRowClick(item, event: event) }
                        )
                        .id(item.id)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: RowFramePreferenceKey.self,
                                    value: [item.id: proxy.frame(in: .global)]
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(AppTheme.appBackground)
            .coordinateSpace(name: "historyList")
            .background(
                ScrollViewResolver { scrollView in
                    historyScrollView = scrollView
                }
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HistoryViewportFramePreferenceKey.self,
                        value: proxy.frame(in: .global)
                    )
                }
            )
            .background(KeyboardCaptureView { event in
                handleKey(event, scrollProxy: proxy)
            })
            .background(
                DragSelectionCaptureView(
                    isEnabled: !showingSettings,
                    viewportFrame: historyViewportFrame,
                    onDrag: { location, shouldSelect in
                        handleDragSelection(at: location, scrollProxy: proxy, shouldSelect: shouldSelect)
                    },
                    onEnd: {
                        endDragSelection()
                    }
                )
            )
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        handleDragSelection(at: value.location, scrollProxy: proxy, shouldSelect: true)
                    }
                    .onEnded { _ in endDragSelection() }
            )
            .onPreferenceChange(RowFramePreferenceKey.self) { frames in
                rowFrames = frames
            }
            .onPreferenceChange(HistoryViewportFramePreferenceKey.self) { frame in
                historyViewportFrame = frame
            }
            .onChange(of: store.items.first?.id) { newID in
                guard let newID else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(newID, anchor: .top)
                }
            }
            .onChange(of: searchText) { _ in
                clearSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                clearSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: SelectionColorPreferences.changedNotification)) { _ in
                selectionColor = SelectionColorPreferences.color
            }
            .onReceive(NotificationCenter.default.publisher(for: AppIconPreferences.changedNotification)) { notification in
                appIconChoice = notification.object as? AppIconChoice ?? AppIconPreferences.selected
            }
            .onReceive(NotificationCenter.default.publisher(for: ClearSelectionHotKeyDefaults.changedNotification)) { notification in
                clearSelectionHotKey = notification.object as? HotKeyConfiguration ?? ClearSelectionHotKeyDefaults.load()
            }
            .onReceive(NotificationCenter.default.publisher(for: PinHotKeyDefaults.changedNotification)) { notification in
                pinHotKey = notification.object as? HotKeyConfiguration ?? PinHotKeyDefaults.load()
            }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.iconBackground)
                    if let image = appIconChoice.previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    } else {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.iconForeground)
                    }
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ClipShelf")
                        .font(.system(size: 17, weight: .semibold))
                    Text(watcher.statusText)
                        .font(.caption)
                        .foregroundStyle(watcher.isRunning ? Color.secondary : Color.orange)
                }

                Spacer()

                Button {
                    watcher.chooseFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("选择截图文件夹")

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("设置")

                Button {
                    togglePinnedForActionItems()
                } label: {
                    Image(systemName: "pin")
                }
                .buttonStyle(.borderless)
                .disabled(actionItems.isEmpty)
                .help("置顶选中的记录")

                Button(role: .destructive) {
                    deleteSelectedOrClear()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(selectedIDs.isEmpty ? "清空记录" : "删除选中的记录")
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索文字、文件名、截图名", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AppTheme.searchBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.subtleBorder, lineWidth: 1)
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(AppTheme.appBackground)
    }

    private func deleteSelectedOrClear() {
        if selectedIDs.isEmpty {
            store.clearHistory()
        } else {
            store.remove(ids: selectedIDs)
        }
        clearSelection()
    }

    private func clearSelection() {
        selectedIDs.removeAll()
        focusedID = nil
        anchorID = nil
        dragAnchorID = nil
        isDragSelecting = false
        stopAutoScroll()
    }

    private func handleKey(_ event: NSEvent, scrollProxy: ScrollViewProxy? = nil) {
        if event.modifierFlags.contains(.command) {
            handleCommandKey(event)
            return
        }

        switch event.keyCode {
        case 126:
            moveFocus(delta: -1, scrollProxy: scrollProxy)
        case 125:
            moveFocus(delta: 1, scrollProxy: scrollProxy)
        case 49:
            guard selectedIDs.count <= 1 else { return }
            if let item = previewItems.first {
                PreviewController.shared.togglePreview(selectedIDs.isEmpty ? [item] : previewItems)
            }
        case 36, 76:
            if let item = focusedItem {
                store.paste(item)
            }
        case 51, 117:
            deleteSelectedOrClear()
        default:
            break
        }
    }

    private func installCommandKeyMonitorIfNeeded() {
        guard commandKeyMonitor == nil else { return }
        commandKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !showingSettings,
                  event.window === NSApp.keyWindow else {
                return event
            }

            if clearSelectionHotKey.matches(event) {
                clearSelection()
                return nil
            }

            if pinHotKey.matches(event) {
                togglePinnedForActionItems()
                return nil
            }

            if event.modifierFlags.contains(.command),
               ["a", "c", "v"].contains(event.charactersIgnoringModifiers?.lowercased()) {
                handleCommandKey(event)
                return nil
            }

            return event
        }
    }

    private func removeCommandKeyMonitor() {
        if let commandKeyMonitor {
            NSEvent.removeMonitor(commandKeyMonitor)
            self.commandKeyMonitor = nil
        }
    }

    private func handleCommandKey(_ event: NSEvent) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a":
            selectAllVisibleItems()
        case "c":
            store.copy(actionItems)
        case "v":
            store.paste(actionItems)
        default:
            break
        }
    }

    private var focusedItem: ClipItem? {
        guard let focusedID else { return nil }
        return filteredItems.first { $0.id == focusedID }
    }

    private var actionItems: [ClipItem] {
        let selected = filteredItems.filter { selectedIDs.contains($0.id) }
        if !selected.isEmpty {
            return selected
        }

        if let focusedItem {
            return [focusedItem]
        }

        return []
    }

    private func selectAllVisibleItems() {
        selectedIDs = Set(filteredItems.map(\.id))
        focusedID = filteredItems.first?.id
        anchorID = focusedID
    }

    private func togglePinnedForActionItems() {
        let items = actionItems
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty else { return }
        store.togglePinned(ids: ids)
        selectedIDs = ids
        focusedID = items.first?.id ?? focusedID
        anchorID = focusedID
    }

    private func moveFocus(delta: Int, scrollProxy: ScrollViewProxy? = nil) {
        guard !filteredItems.isEmpty else {
            focusedID = nil
            selectedIDs.removeAll()
            anchorID = nil
            return
        }

        let currentIndex: Int
        if let focusedID, let index = filteredItems.firstIndex(where: { $0.id == focusedID }) {
            currentIndex = index
        } else {
            currentIndex = delta > 0 ? -1 : filteredItems.count
        }
        let nextIndex = min(max(currentIndex + delta, 0), filteredItems.count - 1)
        guard nextIndex != currentIndex else { return }

        let nextID = filteredItems[nextIndex].id
        focusedID = nextID
        selectedIDs = [nextID]
        anchorID = nextID
        scrollFocusedItemIntoView(nextID, delta: delta, scrollProxy: scrollProxy)
    }

    private func scrollFocusedItemIntoView(_ id: ClipItem.ID, delta: Int, scrollProxy: ScrollViewProxy?) {
        if scrollNativeFocusedItemIntoView(id) {
            return
        }

        scrollFocusedItemToEdge(id, delta: delta, scrollProxy: scrollProxy)
    }

    private func scrollFocusedItemToEdge(_ id: ClipItem.ID, delta: Int, scrollProxy: ScrollViewProxy?) {
        guard let scrollProxy else { return }
        scrollProxy.scrollTo(id, anchor: delta > 0 ? .bottom : .top)
    }

    private func scrollNativeFocusedItemIntoView(_ id: ClipItem.ID) -> Bool {
        guard let scrollView = historyScrollView,
              let rowFrame = rowFrames[id],
              !historyViewportFrame.isEmpty else {
            return false
        }

        let topMargin: CGFloat = 18
        let bottomMargin: CGFloat = 18
        let visibleTop = historyViewportFrame.minY + topMargin
        let visibleBottom = historyViewportFrame.maxY - bottomMargin

        if rowFrame.minY >= visibleTop && rowFrame.maxY <= visibleBottom {
            return true
        }

        let delta: CGFloat
        if rowFrame.minY < visibleTop {
            delta = rowFrame.minY - visibleTop
        } else {
            delta = rowFrame.maxY - visibleBottom
        }

        guard abs(delta) > 0.5 else { return true }

        scrollHistoryViewByGlobalDelta(delta, scrollView: scrollView)
        return true
    }

    private func scrollHistoryViewByGlobalDelta(_ delta: CGFloat, scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else { return }
        let clipView = scrollView.contentView
        let visible = clipView.bounds
        let maxY = max(0, documentView.bounds.height - visible.height)
        let sign: CGFloat = documentView.isFlipped ? 1 : -1
        let proposedY = min(max(visible.origin.y + delta * sign, 0), maxY)
        guard proposedY != visible.origin.y else { return }

        clipView.scroll(to: CGPoint(x: visible.origin.x, y: proposedY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func toggleSelectionForKeyboard(_ id: ClipItem.ID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        anchorID = id
    }

    private func handleRowClick(_ item: ClipItem, event: NSEvent?) {
        focusedID = item.id

        let modifiers = event?.modifierFlags ?? []
        if modifiers.contains(.shift), let anchorID {
            selectRange(from: anchorID, to: item.id)
        } else if modifiers.contains(.command) {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
            anchorID = item.id
        } else if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
            anchorID = nil
        } else {
            selectedIDs = [item.id]
            anchorID = item.id
        }
    }

    private func selectRange(from firstID: ClipItem.ID, to secondID: ClipItem.ID) {
        guard let firstIndex = filteredItems.firstIndex(where: { $0.id == firstID }),
              let secondIndex = filteredItems.firstIndex(where: { $0.id == secondID }) else {
            selectedIDs = [secondID]
            anchorID = secondID
            return
        }

        let bounds = min(firstIndex, secondIndex)...max(firstIndex, secondIndex)
        selectedIDs = Set(bounds.map { filteredItems[$0].id })
    }

    private var previewItems: [ClipItem] {
        let selected = filteredItems.filter { selectedIDs.contains($0.id) }
        if !selected.isEmpty {
            return selected
        }

        if let focusedItem {
            return [focusedItem]
        }

        return []
    }

    private func beginDragSelection(at id: ClipItem.ID) {
        isDragSelecting = true
        dragAnchorID = id
        anchorID = id
        focusedID = id
        selectedIDs = [id]
    }

    private func extendDragSelection(to id: ClipItem.ID) {
        guard isDragSelecting, let dragAnchorID else { return }
        focusedID = id
        selectRange(from: dragAnchorID, to: id)
    }

    private func endDragSelection() {
        isDragSelecting = false
        dragAnchorID = nil
        stopAutoScroll()
    }

    private func handleDragSelection(at location: CGPoint, scrollProxy: ScrollViewProxy, shouldSelect: Bool) {
        updateAutoScroll(for: location, scrollProxy: scrollProxy)
        guard shouldSelect else { return }
        guard let id = rowID(at: location) ?? edgeRowID(for: location) else { return }

        if !isDragSelecting {
            beginDragSelection(at: id)
        } else {
            extendDragSelection(to: id)
        }
    }

    private func updateAutoScroll(for location: CGPoint, scrollProxy: ScrollViewProxy) {
        let direction = autoScrollDirection(for: location)

        if direction == 0 {
            stopAutoScroll()
        } else {
            startAutoScroll(direction: direction, scrollProxy: scrollProxy)
        }
    }

    private func autoScrollDirection(for location: CGPoint) -> Int {
        if !historyViewportFrame.isEmpty {
            let edgeDistance: CGFloat = 120
            if location.y < historyViewportFrame.minY + edgeDistance {
                return -1
            }

            if location.y > historyViewportFrame.maxY - edgeDistance {
                return 1
            }
        }

        guard let id = rowID(at: location),
              let index = filteredItems.firstIndex(where: { $0.id == id }) else {
            return 0
        }

        let visibleIDs = visibleItemIDs()
        guard let visibleIndex = visibleIDs.firstIndex(of: id) else { return 0 }

        if visibleIndex <= 1, index > 0 {
            return -1
        }

        if visibleIndex >= max(visibleIDs.count - 2, 0), index < filteredItems.count - 1 {
            return 1
        }

        return 0
    }

    private func startAutoScroll(direction: Int, scrollProxy: ScrollViewProxy) {
        guard autoScrollDirection != direction || autoScrollTimer == nil else { return }
        stopAutoScroll()
        autoScrollDirection = direction
        autoScroll(direction: direction, scrollProxy: scrollProxy)
        let timer = Timer(timeInterval: 0.08, repeats: true) { _ in
            autoScroll(direction: direction, scrollProxy: scrollProxy)
        }
        autoScrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollDirection = 0
    }

    private func autoScroll(direction: Int, scrollProxy: ScrollViewProxy) {
        guard isDragSelecting, !filteredItems.isEmpty else {
            stopAutoScroll()
            return
        }

        let currentIndex = focusedID.flatMap { id in
            filteredItems.firstIndex { $0.id == id }
        } ?? (direction > 0 ? 0 : filteredItems.count - 1)
        let nextIndex = min(max(currentIndex + direction * 2, 0), filteredItems.count - 1)
        guard nextIndex != currentIndex else { return }

        let nextID = filteredItems[nextIndex].id
        focusedID = nextID
        extendDragSelection(to: nextID)

        if scrollNativeHistoryView(direction: direction) {
            return
        }

        scrollProxy.scrollTo(nextID, anchor: direction > 0 ? .bottom : .top)
    }

    private func scrollNativeHistoryView(direction: Int) -> Bool {
        guard let scrollView = historyScrollView,
              let documentView = scrollView.documentView else {
            NSLog("ClipShelf auto-scroll: missing NSScrollView")
            return false
        }

        let clipView = scrollView.contentView
        let visible = clipView.bounds
        let maxY = max(0, documentView.bounds.height - visible.height)
        let sign: CGFloat = documentView.isFlipped ? 1 : -1
        let delta: CGFloat = CGFloat(direction) * sign * 72
        let proposedY = min(max(visible.origin.y + delta, 0), maxY)
        guard proposedY != visible.origin.y else {
            NSLog("ClipShelf auto-scroll: at edge direction=\(direction) origin=\(visible.origin.y) maxY=\(maxY) flipped=\(documentView.isFlipped)")
            return false
        }

        clipView.scroll(to: CGPoint(x: visible.origin.x, y: proposedY))
        scrollView.reflectScrolledClipView(clipView)
        NSLog("ClipShelf auto-scroll: scrolled direction=\(direction) from=\(visible.origin.y) to=\(proposedY) maxY=\(maxY) flipped=\(documentView.isFlipped)")
        return true
    }

    private func rowID(at location: CGPoint) -> ClipItem.ID? {
        rowFrames
            .filter { $0.value.minY <= location.y && location.y <= $0.value.maxY }
            .min { abs($0.value.midY - location.y) < abs($1.value.midY - location.y) }?
            .key
    }

    private func edgeRowID(for location: CGPoint) -> ClipItem.ID? {
        if !historyViewportFrame.isEmpty, location.y < historyViewportFrame.minY {
            return rowFrames.min { $0.value.minY < $1.value.minY }?.key
        }

        if !historyViewportFrame.isEmpty, location.y > historyViewportFrame.maxY {
            return rowFrames.max { $0.value.maxY < $1.value.maxY }?.key
        }

        return nil
    }

    private func visibleItemIDs() -> [ClipItem.ID] {
        guard !historyViewportFrame.isEmpty else { return [] }

        return filteredItems.compactMap { item in
            guard let frame = rowFrames[item.id],
                  frame.maxY >= historyViewportFrame.minY,
                  frame.minY <= historyViewportFrame.maxY else {
                return nil
            }

            return item.id
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("还没有记录")
                .font(.system(size: 17, weight: .semibold))
            Text("复制文字或文件，或者截一张图。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.appBackground)
    }
}

private struct ClipRow: View {
    let item: ClipItem
    @ObservedObject var store: ClipStore
    let isFocused: Bool
    let isSelected: Bool
    let selectionColor: Color
    let handleClick: (NSEvent?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            preview
                .frame(width: 52, height: 40)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if item.isPinned {
                        Label("已置顶", systemImage: "pin.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    Text(kindText)
                    Text(DateText.formatter.string(from: item.createdAt))
                }
                .font(.caption)
                .foregroundStyle(isSelected ? Color.black.opacity(0.72) : Color.secondary)
            }

            Spacer()

            Button {
                store.togglePinned(item)
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(ChatGPTIconButtonStyle(isSelected: isSelected))
            .delayedTooltip(item.isPinned ? "取消置顶" : "置顶")

            Button {
                store.copy(item)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(ChatGPTIconButtonStyle(isSelected: isSelected))
            .delayedTooltip("复制")

            Button {
                store.paste(item)
            } label: {
                Image(systemName: "arrow.down.doc")
            }
            .buttonStyle(ChatGPTIconButtonStyle(isSelected: isSelected))
            .delayedTooltip("粘贴")

            Button(role: .destructive) {
                store.remove(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(ChatGPTIconButtonStyle(isSelected: isSelected))
            .delayedTooltip("删除记录")
        }
        .frame(height: 58)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .foregroundStyle(isSelected ? Color.black : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.clear : AppTheme.subtleBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleClick(NSApp.currentEvent)
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return selectionColor
        }

        if isFocused {
            return AppTheme.rowBackground
        }

        return AppTheme.rowBackground
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.textPreviewBackground)
                .overlay(Image(systemName: "text.alignleft").foregroundStyle(AppTheme.textPreviewForeground))
        case .file:
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.filePreviewBackground)
                .overlay(Image(systemName: "doc").foregroundStyle(AppTheme.filePreviewForeground))
        case .image:
            if let data = item.imageData, let image = NSImage(data: data) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.black.opacity(0.06))
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.imagePreviewBackground)
                    .overlay(Image(systemName: "photo").foregroundStyle(AppTheme.imagePreviewForeground))
            }
        }
    }

    private var kindText: String {
        switch item.kind {
        case .text: "文字"
        case .file: item.filePaths.count > 1 ? "\(item.filePaths.count) 个文件" : "文件"
        case .image: item.sourcePath == nil ? "图片" : "截图"
        }
    }
}

private enum AppTheme {
    static let appBackground = Color(nsColor: .windowBackgroundColor)
    static let rowBackground = Color(nsColor: .textBackgroundColor)
    static let searchBackground = Color(nsColor: .textBackgroundColor)
    static let subtleBorder = Color(nsColor: .separatorColor).opacity(0.42)
    static let focusedBackground = Color(nsColor: .controlAccentColor).opacity(0.10)
    static let selectedBackground = Color(nsColor: .labelColor).opacity(0.90)
    static let iconBackground = Color(nsColor: .labelColor).opacity(0.92)
    static let iconForeground = Color(nsColor: .windowBackgroundColor)
    static let textPreviewBackground = Color(red: 0.90, green: 0.95, blue: 0.98)
    static let textPreviewForeground = Color(red: 0.10, green: 0.32, blue: 0.42)
    static let filePreviewBackground = Color(red: 0.91, green: 0.96, blue: 0.92)
    static let filePreviewForeground = Color(red: 0.12, green: 0.38, blue: 0.20)
    static let imagePreviewBackground = Color(red: 0.98, green: 0.94, blue: 0.88)
    static let imagePreviewForeground = Color(red: 0.56, green: 0.30, blue: 0.04)
}

private struct ChatGPTIconButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isSelected ? Color.black : Color.secondary)
            .frame(width: 36, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Color.black.opacity(configuration.isPressed ? 0.12 : 0.07) : Color(nsColor: .controlBackgroundColor).opacity(configuration.isPressed ? 1 : 0.72))
            )
    }
}

private extension View {
    func delayedTooltip(_ text: String) -> some View {
        modifier(DelayedTooltipModifier(text: text))
    }
}

private struct DelayedTooltipModifier: ViewModifier {
    let text: String
    @State private var isHovering = false
    @State private var isVisible = false
    @State private var hoverTask: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isVisible {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.black.opacity(0.86))
                        )
                        .fixedSize()
                        .offset(y: -34)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovering in
                isHovering = hovering
                hoverTask?.cancel()

                if hovering {
                    let task = DispatchWorkItem {
                        if isHovering {
                            withAnimation(.easeOut(duration: 0.12)) {
                                isVisible = true
                            }
                        }
                    }
                    hoverTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: task)
                } else {
                    withAnimation(.easeOut(duration: 0.08)) {
                        isVisible = false
                    }
                }
            }
    }
}

private struct RowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [ClipItem.ID: CGRect] = [:]

    static func reduce(value: inout [ClipItem.ID: CGRect], nextValue: () -> [ClipItem.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HistoryViewportFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct ScrollViewResolver: NSViewRepresentable {
    let onResolve: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onResolve(resolveScrollView(from: view))
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(resolveScrollView(from: nsView))
        }
    }

    private func resolveScrollView(from view: NSView) -> NSScrollView? {
        if let enclosing = view.enclosingScrollView {
            return enclosing
        }

        guard let windowContent = view.window?.contentView else {
            return nil
        }

        return firstScrollView(in: windowContent)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = firstScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }
}

private struct KeyboardCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            if nsView.window?.firstResponder == nil {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private final class KeyCaptureNSView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           ["a", "c", "v"].contains(event.charactersIgnoringModifiers?.lowercased()) {
            onKeyDown?(event)
            return
        }

        switch event.keyCode {
        case 36, 49, 51, 76, 117, 125, 126:
            onKeyDown?(event)
        default:
            super.keyDown(with: event)
        }
    }
}

private struct DragSelectionCaptureView: NSViewRepresentable {
    let isEnabled: Bool
    let viewportFrame: CGRect
    let onDrag: (CGPoint, Bool) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.viewportFrame = viewportFrame
        context.coordinator.onDrag = onDrag
        context.coordinator.onEnd = onEnd
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var viewportFrame: CGRect = .zero
        var onDrag: ((CGPoint, Bool) -> Void)?
        var onEnd: (() -> Void)?
        var isEnabled = true
        weak var view: NSView?

        private var monitor: Any?
        private var startedInViewport = false
        private var didDrag = false

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled,
                  event.window === NSApp.keyWindow,
                  let point = swiftUIGlobalPoint(from: event) else {
                return event
            }

            switch event.type {
            case .leftMouseDown:
                startedInViewport = viewportFrame.contains(point)
                didDrag = false
                return event
            case .leftMouseDragged:
                guard startedInViewport else { return event }
                didDrag = true
                onDrag?(point, false)
                return event
            case .leftMouseUp:
                guard startedInViewport else { return event }
                startedInViewport = false
                onEnd?()
                return event
            default:
                return event
            }
        }

        private func swiftUIGlobalPoint(from event: NSEvent) -> CGPoint? {
            guard let view else { return nil }
            let pointInView = view.convert(event.locationInWindow, from: nil)
            return CGPoint(
                x: viewportFrame.minX + pointInView.x,
                y: viewportFrame.maxY - pointInView.y
            )
        }
    }
}
