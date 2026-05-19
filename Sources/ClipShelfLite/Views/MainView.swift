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
    @State private var autoScrollTimer: Timer?
    @State private var autoScrollDirection = 0
    @State private var historyScrollView: NSScrollView?
    @State private var selectionColor = SelectionColorPreferences.color
    @State private var switchToClickedRecord = SelectionClickBehaviorPreferences.switchToClickedRecord
    @State private var multiSelectionClickSelectedBehavior = SelectionClickBehaviorPreferences.multiSelectionClickSelectedBehavior
    @State private var multiSelectionClickUnselectedBehavior = SelectionClickBehaviorPreferences.multiSelectionClickUnselectedBehavior
    @State private var postDragClickRecoveryDuration = DragSelectionPreferences.clickRecoveryDuration
    @State private var commandKeyMonitor: Any?
    @State private var appIconChoice = AppIconPreferences.selected
    @State private var clearSelectionHotKey = ClearSelectionHotKeyDefaults.load()
    @State private var pinHotKey = PinHotKeyDefaults.load()
    @State private var suppressPasteUntil = Date.distantPast
    @State private var suppressRowTapUntil = Date.distantPast
    private let historyRowHeight: CGFloat = 74
    private let historyListHorizontalInset: CGFloat = 10
    private let historyListVerticalInset: CGFloat = 8

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
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        let isSelected = selectedIDs.contains(item.id)
                        let isNextSelected = index + 1 < filteredItems.count && selectedIDs.contains(filteredItems[index + 1].id)
                        ClipRow(
                            item: item,
                            store: store,
                            isFocused: focusedID == item.id,
                            isSelected: isSelected,
                            selectionColor: selectionColor,
                            showsSeparator: index < filteredItems.count - 1 && !isSelected && !isNextSelected,
                            handleClick: { event in handleRowClick(item, event: event) },
                            handleCopy: { store.copy(actionItems(for: item)) },
                            handlePaste: { pasteRowItems(actionItems(for: item)) }
                        )
                        .id(item.id)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.rowBackground)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.subtleBorder, lineWidth: 1)
                )
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
            .background(KeyboardCaptureView { event in
                handleKey(event, scrollProxy: proxy)
            })
            .background(
                DragSelectionCaptureView(
                    isEnabled: !showingSettings,
                    clickRecoveryDuration: postDragClickRecoveryDuration,
                    onPointerDown: { location in
                        handleHistoryPointerDown(at: location)
                    },
                    onSmallDragClick: { location, event in
                        handleHistorySmallDragClick(at: location, event: event)
                    },
                    onDrag: { location, shouldSelect in
                        handleDragSelection(at: location, scrollProxy: proxy, shouldSelect: shouldSelect)
                    },
                    onEnd: {
                        endDragSelection()
                    },
                    onCancel: {
                        endDragSelection()
                    }
                )
            )
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
            .onReceive(NotificationCenter.default.publisher(for: SelectionClickBehaviorPreferences.changedNotification)) { notification in
                switchToClickedRecord = notification.object as? Bool ?? SelectionClickBehaviorPreferences.switchToClickedRecord
                multiSelectionClickSelectedBehavior = SelectionClickBehaviorPreferences.multiSelectionClickSelectedBehavior
                multiSelectionClickUnselectedBehavior = SelectionClickBehaviorPreferences.multiSelectionClickUnselectedBehavior
            }
            .onReceive(NotificationCenter.default.publisher(for: DragSelectionPreferences.changedNotification)) { notification in
                postDragClickRecoveryDuration = notification.object as? TimeInterval ?? DragSelectionPreferences.clickRecoveryDuration
                if postDragClickRecoveryDuration <= 0 {
                    suppressRowTapUntil = .distantPast
                }
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
                Group {
                    if let image = appIconChoice.previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
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
                    copyActionItems()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(actionItems.isEmpty)
                .help(copyActionHelp)

                Button {
                    pasteActionItems()
                } label: {
                    Image(systemName: "arrow.down.doc")
                }
                .buttonStyle(.borderless)
                .disabled(actionItems.isEmpty)
                .help(pasteActionHelp)

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
            moveFocus(delta: -1)
        case 125:
            moveFocus(delta: 1)
        case 49:
            let items = previewItems
            if !items.isEmpty {
                PreviewController.shared.togglePreview(items, onNavigate: navigatePreview)
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
            guard shouldHandleMainWindowKeyEvent(event) else {
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

            if event.keyCode == 53 {
                if !searchText.isEmpty {
                    clearSearchState()
                    return nil
                }
            }

            if (event.keyCode == 125 || event.keyCode == 126),
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control) {
                handleKey(event)
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

    private func shouldHandleMainWindowKeyEvent(_ event: NSEvent) -> Bool {
        guard !showingSettings,
              let window = event.window,
              window === NSApp.keyWindow,
              window.title == "ClipShelf" else {
            return false
        }

        return true
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

    private func clearSearchState() {
        searchText = ""
        clearSelection()
        NSApp.keyWindow?.makeFirstResponder(nil)
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

    private func actionItems(for rowItem: ClipItem) -> [ClipItem] {
        if selectedIDs.contains(rowItem.id) {
            let selected = filteredItems.filter { selectedIDs.contains($0.id) }
            if !selected.isEmpty {
                return selected
            }
        }

        return [rowItem]
    }

    private var copyActionHelp: String {
        selectedIDs.count > 1 ? "复制选中的 \(selectedIDs.count) 条记录" : "复制当前记录"
    }

    private var pasteActionHelp: String {
        selectedIDs.count > 1 ? "粘贴选中的 \(selectedIDs.count) 条记录" : "粘贴当前记录"
    }

    private func copyActionItems() {
        let items = actionItems
        guard !items.isEmpty else { return }
        store.copy(items)
    }

    private func pasteActionItems() {
        let items = actionItems
        guard !items.isEmpty else { return }
        store.paste(items)
    }

    private func pasteRowItems(_ items: [ClipItem]) {
        guard Date() >= suppressPasteUntil else { return }
        store.paste(items)
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

    private func moveFocus(delta: Int) {
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
            currentIndex = initialKeyboardIndex(for: delta)
        }
        let nextIndex = min(max(currentIndex + delta, 0), filteredItems.count - 1)
        guard nextIndex != currentIndex else { return }

        let nextID = filteredItems[nextIndex].id
        focusedID = nextID
        selectedIDs = [nextID]
        anchorID = nextID

        revealKeyboardSelectionIfNeeded(nextID, direction: delta)
    }

    private func initialKeyboardIndex(for delta: Int) -> Int {
        let visibleIndices = visibleItemIndices()
        if delta > 0 {
            return (visibleIndices.first ?? -1) - 1
        }

        return (visibleIndices.last ?? filteredItems.count) + 1
    }

    private func revealKeyboardSelectionIfNeeded(_ id: ClipItem.ID, direction: Int) {
        guard let scrollView = historyScrollView,
              let index = filteredItems.firstIndex(where: { $0.id == id }) else { return }

        if let rowFrame = rowFrameInViewport(at: index, in: scrollView),
           let delta = scrollDeltaToReveal(rowFrame, in: scrollView) {
            scrollHistoryViewByGlobalDelta(delta, scrollView: scrollView)
        }
    }

    private func scrollDeltaToReveal(_ rowFrame: CGRect, in scrollView: NSScrollView) -> CGFloat? {
        let visibleHeight = scrollView.contentView.bounds.height
        guard visibleHeight > 0 else { return nil }

        let topPadding: CGFloat = 6
        let bottomPadding: CGFloat = 18
        let visibleTop = topPadding
        let visibleBottom = visibleHeight - bottomPadding

        if rowFrame.minY < visibleTop {
            return rowFrame.minY - visibleTop
        }

        if rowFrame.maxY > visibleBottom {
            return rowFrame.maxY - visibleBottom
        }

        return nil
    }

    private func rowFrameInViewport(at index: Int, in scrollView: NSScrollView) -> CGRect? {
        guard filteredItems.indices.contains(index),
              let visibleRange = visibleContentRange(in: scrollView) else { return nil }

        let rowMinY = historyListVerticalInset + CGFloat(index) * historyRowHeight
        return CGRect(
            x: 0,
            y: rowMinY - visibleRange.lowerBound,
            width: scrollView.contentView.bounds.width,
            height: historyRowHeight
        )
    }

    private func visibleContentRange(in scrollView: NSScrollView) -> ClosedRange<CGFloat>? {
        guard let documentView = scrollView.documentView else { return nil }

        let visible = scrollView.contentView.bounds
        guard visible.height > 0 else { return nil }

        if documentView.isFlipped {
            return visible.minY...visible.maxY
        }

        let documentHeight = documentView.bounds.height
        return max(0, documentHeight - visible.maxY)...max(0, documentHeight - visible.minY)
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

    private func visibleItemIndices() -> [Int] {
        guard let scrollView = historyScrollView,
              !filteredItems.isEmpty,
              let range = visibleContentRange(in: scrollView) else { return [] }

        let first = max(0, Int(floor((range.lowerBound - historyListVerticalInset) / historyRowHeight)))
        let last = min(filteredItems.count - 1, Int(floor((range.upperBound - historyListVerticalInset) / historyRowHeight)))
        guard first <= last else { return [] }

        return Array(first...last)
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
        guard Date() >= suppressRowTapUntil else { return }

        let modifiers = event?.modifierFlags ?? []
        if modifiers.contains(.shift), let anchorID {
            focusedID = item.id
            selectRange(from: anchorID, to: item.id)
        } else if modifiers.contains(.command) {
            focusedID = item.id
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
            anchorID = item.id
        } else if selectedIDs.count > 1 {
            handleMultiSelectionClick(on: item)
        } else if selectedIDs.count == 1 {
            handleSingleSelectionClick(on: item)
        } else {
            collapseSelection(to: item)
        }
    }

    private func handleSingleSelectionClick(on item: ClipItem) {
        if selectedIDs.contains(item.id) || !switchToClickedRecord {
            clearSelection()
        } else {
            collapseSelection(to: item)
        }
    }

    private func handleMultiSelectionClick(on item: ClipItem) {
        if selectedIDs.contains(item.id) {
            switch multiSelectionClickSelectedBehavior {
            case .collapseToClicked:
                collapseSelection(to: item)
            case .clearAll:
                clearSelection()
            case .removeClicked:
                removeClickedItemFromMultiSelection(item)
            }
        } else {
            switch multiSelectionClickUnselectedBehavior {
            case .collapseToClicked:
                collapseSelection(to: item)
            case .clearAll:
                clearSelection()
            }
        }
    }

    private func removeClickedItemFromMultiSelection(_ item: ClipItem) {
        selectedIDs.remove(item.id)
        guard selectedIDs.count > 1 else {
            clearSelection()
            return
        }

        focusedID = selectedIDs.first
        anchorID = focusedID
    }

    private func collapseSelection(to item: ClipItem) {
        focusedID = item.id
        selectedIDs = [item.id]
        anchorID = item.id
    }

    private func handleHistoryPointerDown(at location: CGPoint) {
        guard !selectedIDs.isEmpty || focusedID != nil else { return }
        guard rowID(at: location) == nil else { return }
        clearSelection()
    }

    private func handleHistorySmallDragClick(at location: CGPoint, event: NSEvent?) {
        guard let id = rowID(at: location),
              let item = filteredItems.first(where: { $0.id == id }) else { return }
        if postDragClickRecoveryDuration > 0 {
            suppressRowTapUntil = Date().addingTimeInterval(0.18)
        }
        collapseSelectionFromRecoveredClick(to: item)
    }

    private func collapseSelectionFromRecoveredClick(to item: ClipItem) {
        if selectedIDs.count > 1 {
            handleMultiSelectionClick(on: item)
        } else if selectedIDs.count == 1 {
            handleSingleSelectionClick(on: item)
        } else {
            collapseSelection(to: item)
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
        if selected.count == 1 {
            return selected
        }

        if selected.count > 1 {
            return []
        }

        if let focusedItem {
            return [focusedItem]
        }

        return []
    }

    private func navigatePreview(direction: Int) -> Bool {
        guard !filteredItems.isEmpty else { return false }

        let currentID = focusedID ?? selectedIDs.first
        guard let currentID,
              let currentIndex = filteredItems.firstIndex(where: { $0.id == currentID }) else {
            return false
        }

        let nextIndex = min(max(currentIndex + direction, 0), filteredItems.count - 1)
        guard nextIndex != currentIndex else { return false }

        let item = filteredItems[nextIndex]
        collapseSelection(to: item)
        revealKeyboardSelectionIfNeeded(item.id, direction: direction)
        PreviewController.shared.preview([item], onNavigate: navigatePreview)
        return true
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
        if isDragSelecting {
            suppressPasteUntil = Date().addingTimeInterval(0.45)
        }
        isDragSelecting = false
        dragAnchorID = nil
        stopAutoScroll()
    }

    private func handleDragSelection(at location: CGPoint, scrollProxy: ScrollViewProxy, shouldSelect: Bool) {
        stopAutoScroll()
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
        if let viewportSize = historyViewportSize {
            let edgeDistance = min(CGFloat(120), viewportSize.height * 0.28)
            if location.y < edgeDistance {
                return -1
            }

            if location.y > viewportSize.height - edgeDistance {
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
        rowID(atViewportPoint: location)
    }

    private func rowID(atViewportPoint location: CGPoint) -> ClipItem.ID? {
        guard let scrollView = historyScrollView,
              let visibleRange = visibleContentRange(in: scrollView) else { return nil }
        let viewportSize = scrollView.contentView.bounds.size
        guard viewportSize.width > 0,
              viewportSize.height > 0,
              location.x >= historyListHorizontalInset,
              location.x <= viewportSize.width - historyListHorizontalInset,
              location.y >= 0,
              location.y <= viewportSize.height else { return nil }

        let yInList = visibleRange.lowerBound + location.y - historyListVerticalInset
        guard yInList >= 0 else { return nil }

        let index = Int(floor(yInList / historyRowHeight))
        guard filteredItems.indices.contains(index) else { return nil }
        return filteredItems[index].id
    }

    private func edgeRowID(for location: CGPoint) -> ClipItem.ID? {
        guard let viewportSize = historyViewportSize else { return nil }

        if location.y < 0 {
            return visibleItemIndices().first.map { filteredItems[$0].id } ?? filteredItems.first?.id
        }

        if location.y > viewportSize.height {
            return visibleItemIndices().last.map { filteredItems[$0].id } ?? filteredItems.last?.id
        }

        return nil
    }

    private var historyViewportSize: CGSize? {
        guard let scrollView = historyScrollView else { return nil }
        let size = scrollView.contentView.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }

    private func visibleItemIDs() -> [ClipItem.ID] {
        visibleItemIndices().map { filteredItems[$0].id }
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
    let showsSeparator: Bool
    let handleClick: (NSEvent?) -> Void
    let handleCopy: () -> Void
    let handlePaste: () -> Void

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
                handleCopy()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(ChatGPTIconButtonStyle(isSelected: isSelected))
            .delayedTooltip(isSelected ? "复制选中的记录" : "复制")

            Button {
                handlePaste()
            } label: {
                Image(systemName: "arrow.down.doc")
            }
            .buttonStyle(ChatGPTIconButtonStyle(isSelected: isSelected))
            .delayedTooltip(isSelected ? "粘贴选中的记录" : "粘贴")

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
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(AppTheme.subtleBorder)
                    .frame(height: 1)
                    .padding(.leading, 76)
                    .padding(.trailing, 12)
            }
        }
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
            return Color.clear
        }

        return Color.clear
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

private struct ScrollViewResolver: NSViewRepresentable {
    let onResolve: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            let scrollView = resolveScrollView(from: view)
            configure(scrollView)
            onResolve(scrollView)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            let scrollView = resolveScrollView(from: nsView)
            configure(scrollView)
            onResolve(scrollView)
        }
    }

    private func configure(_ scrollView: NSScrollView?) {
        guard let scrollView else { return }
        scrollView.usesPredominantAxisScrolling = true
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
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
    let clickRecoveryDuration: TimeInterval
    let onPointerDown: (CGPoint) -> Void
    let onSmallDragClick: (CGPoint, NSEvent?) -> Void
    let onDrag: (CGPoint, Bool) -> Void
    let onEnd: () -> Void
    let onCancel: () -> Void

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
        context.coordinator.setClickRecoveryDuration(clickRecoveryDuration)
        context.coordinator.onPointerDown = onPointerDown
        context.coordinator.onSmallDragClick = onSmallDragClick
        context.coordinator.onDrag = onDrag
        context.coordinator.onEnd = onEnd
        context.coordinator.onCancel = onCancel
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onPointerDown: ((CGPoint) -> Void)?
        var onSmallDragClick: ((CGPoint, NSEvent?) -> Void)?
        var onDrag: ((CGPoint, Bool) -> Void)?
        var onEnd: (() -> Void)?
        var onCancel: (() -> Void)?
        var isEnabled = true
        var clickRecoveryDuration: TimeInterval = DragSelectionPreferences.clickRecoveryDuration
        weak var view: NSView?

        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var startedInViewport = false
        private var didDrag = false
        private var pointerDownPoint: CGPoint?
        private var hadSmallDrag = false
        private var postDragClickRecoveryUntil = Date.distantPast
        private var pendingRecoveredClickPoint: CGPoint?
        private let dragActivationDistance: CGFloat = 6

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel]) { [weak self] event in
                self?.handle(event) ?? event
            }
            observers = [
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.cancelDrag()
                },
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.cancelDrag()
                }
            ]
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            cancelDrag()
        }

        func setClickRecoveryDuration(_ duration: TimeInterval) {
            clickRecoveryDuration = duration
            if duration <= 0 {
                clearPostDragClickRecovery()
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled else {
                cancelDrag()
                return event
            }

            guard event.window === NSApp.keyWindow else {
                cancelDrag()
                return event
            }

            guard let point = localTopLeftPoint(from: event) else {
                cancelDrag()
                return event
            }

            switch event.type {
            case .leftMouseDown:
                if isRecoveringPostDragClick {
                    pendingRecoveredClickPoint = isPointInsideViewport(point) ? point : nil
                    if pendingRecoveredClickPoint != nil {
                        onPointerDown?(point)
                        return nil
                    }
                    clearPostDragClickRecovery()
                }

                startedInViewport = isPointInsideViewport(point)
                didDrag = false
                hadSmallDrag = false
                pointerDownPoint = startedInViewport ? point : nil
                if startedInViewport {
                    onPointerDown?(point)
                }
                return event
            case .leftMouseDragged:
                if isRecoveringPostDragClick {
                    pendingRecoveredClickPoint = isPointInsideViewport(point) ? point : pendingRecoveredClickPoint
                    return nil
                }

                if !startedInViewport {
                    startedInViewport = isPointInsideViewport(point)
                    didDrag = false
                    hadSmallDrag = false
                    pointerDownPoint = startedInViewport ? point : nil
                    if startedInViewport {
                        onPointerDown?(point)
                    }
                }
                guard startedInViewport else { return event }
                guard shouldActivateDrag(at: point) else {
                    hadSmallDrag = true
                    return nil
                }
                didDrag = true
                onDrag?(point, true)
                return nil
            case .leftMouseUp:
                if isRecoveringPostDragClick {
                    let recoveredPoint = isPointInsideViewport(point) ? point : pendingRecoveredClickPoint
                    clearPostDragClickRecovery()
                    if let recoveredPoint {
                        onSmallDragClick?(recoveredPoint, event)
                        return nil
                    }
                    return event
                }

                guard startedInViewport else { return event }
                let shouldConsumeMouseUp = didDrag
                let shouldReplaySmallDragClick = hadSmallDrag && !didDrag
                finishDrag()
                if shouldReplaySmallDragClick {
                    onSmallDragClick?(point, event)
                    return nil
                }
                return shouldConsumeMouseUp ? nil : event
            case .scrollWheel:
                return startedInViewport || didDrag ? nil : event
            default:
                return event
            }
        }

        private func localTopLeftPoint(from event: NSEvent) -> CGPoint? {
            guard let viewport = viewportView() else { return nil }
            let pointInView = viewport.convert(event.locationInWindow, from: nil)
            return CGPoint(
                x: pointInView.x,
                y: viewport.isFlipped ? pointInView.y : viewport.bounds.height - pointInView.y
            )
        }

        private func isPointInsideViewport(_ point: CGPoint) -> Bool {
            guard let view = viewportView() else { return false }
            return point.x >= 0 &&
                point.y >= 0 &&
                point.x <= view.bounds.width &&
                point.y <= view.bounds.height
        }

        private func viewportView() -> NSView? {
            view?.enclosingScrollView?.contentView ?? view
        }

        private func finishDrag() {
            let wasTracking = startedInViewport || didDrag
            let wasDrag = didDrag
            startedInViewport = false
            didDrag = false
            pointerDownPoint = nil
            hadSmallDrag = false
            if wasDrag {
                beginPostDragClickRecovery()
            }
            if wasTracking {
                onEnd?()
            }
        }

        private func cancelDrag() {
            let wasTracking = startedInViewport || didDrag
            let wasDrag = didDrag
            startedInViewport = false
            didDrag = false
            pointerDownPoint = nil
            hadSmallDrag = false
            if wasDrag {
                beginPostDragClickRecovery()
            }
            if wasTracking {
                onCancel?()
            }
        }

        private func shouldActivateDrag(at point: CGPoint) -> Bool {
            guard let pointerDownPoint else { return true }
            let deltaX = point.x - pointerDownPoint.x
            let deltaY = point.y - pointerDownPoint.y
            return hypot(deltaX, deltaY) >= dragActivationDistance
        }

        private var isRecoveringPostDragClick: Bool {
            Date() < postDragClickRecoveryUntil
        }

        private func beginPostDragClickRecovery() {
            guard clickRecoveryDuration > 0 else {
                clearPostDragClickRecovery()
                return
            }

            postDragClickRecoveryUntil = Date().addingTimeInterval(clickRecoveryDuration)
            pendingRecoveredClickPoint = nil
        }

        private func clearPostDragClickRecovery() {
            postDragClickRecoveryUntil = .distantPast
            pendingRecoveredClickPoint = nil
        }
    }
}
