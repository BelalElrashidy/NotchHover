import AppKit

/// Lays widgets out like a CSS flex row: everyone gets their minimum, what is left is
/// shared out by `grow`, and if even the minimums do not fit, the lowest-priority
/// widget is dropped and the row is measured again.
///
/// Widgets are also rebuilt when their size class changes, so a narrow column shows a
/// smaller variant rather than a truncated big one.
final class WidgetRowView: NSView {
    struct Callbacks {
        var onPlayPause: (() -> Void)?
        var onNextTrack: (() -> Void)?
        var onPreviousTrack: (() -> Void)?
        var onOpenSource: (() -> Void)?
        var onShuffle: (() -> Void)?
        var onVolume: ((Int) -> Void)?
        var onSeek: ((Double) -> Void)?
        var onPlayURI: ((String) -> Void)?
        var onSelectShortcut: ((AppShortcut) -> Void)?
        var onStartTimer: ((Int) -> Void)?
        var onCancelTimer: (() -> Void)?
        var onPasteClipboard: ((ClipboardItem) -> Void)?
        var onDismiss: (() -> Void)?
    }

    private struct Slot {
        let widget: PanelWidget
        var view: NSView
        var sizeClass: WidgetSizeClass
    }

    private enum Layout {
        static let gap: CGFloat = 10
        static let dividerWidth: CGFloat = 1
    }

    private let callbacks: Callbacks
    private var slots: [Slot] = []
    private var dividers: [NSView] = []
    private var lastLaidOutWidth: CGFloat = 0

    /// Widgets that did not fit, so the panel can say so.
    private(set) var droppedCount = 0

    init(callbacks: Callbacks) {
        self.callbacks = callbacks
        super.init(frame: .zero)
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        slots = PanelLayoutStore.widgets.map { widget in
            let sizeClass = WidgetSizeClass(width: widget.idealWidth)
            let view = makeView(for: widget, sizeClass: sizeClass)
            addSubview(view)
            return Slot(widget: widget, view: view, sizeClass: sizeClass)
        }
        dividers = []
        lastLaidOutWidth = 0
        needsLayout = true
    }

    // MARK: - Flex layout

    override func layout() {
        super.layout()
        guard bounds.width > 0, slots.isEmpty == false else { return }

        var visible = slots
        var widths = distribute(across: visible, in: bounds.width)

        // Not even the minimums fit: drop the least important and try again.
        while widths == nil, visible.count > 1 {
            guard let index = visible.indices.min(by: {
                visible[$0].widget.dropPriority < visible[$1].widget.dropPriority
            }) else { break }
            visible.remove(at: index)
            widths = distribute(across: visible, in: bounds.width)
        }

        let finalWidths = widths ?? [bounds.width]
        droppedCount = slots.count - visible.count

        let visibleIDs = Set(visible.map(\.widget.rawValue))
        for slot in slots {
            slot.view.isHidden = visibleIDs.contains(slot.widget.rawValue) == false
        }

        rebuildDividers(count: max(0, visible.count - 1))

        var x: CGFloat = 0
        for (index, slot) in visible.enumerated() {
            if index > 0 {
                dividers[index - 1].frame = CGRect(x: x, y: 6, width: Layout.dividerWidth, height: bounds.height - 12)
                x += Layout.dividerWidth + Layout.gap
            }

            let width = finalWidths[index]
            // A width change can cross a size-class boundary, which means a different view.
            let sizeClass = WidgetSizeClass(width: width)
            if let slotIndex = slots.firstIndex(where: { $0.widget == slot.widget }),
               slots[slotIndex].sizeClass != sizeClass {
                slots[slotIndex].view.removeFromSuperview()
                let replacement = makeView(for: slot.widget, sizeClass: sizeClass)
                addSubview(replacement)
                slots[slotIndex].view = replacement
                slots[slotIndex].sizeClass = sizeClass
                replacement.frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
            } else {
                slot.view.frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
            }

            x += width + Layout.gap
        }

        lastLaidOutWidth = bounds.width
    }

    /// Returns nil when the minimums alone overflow the row.
    private func distribute(across slots: [Slot], in available: CGFloat) -> [CGFloat]? {
        guard slots.isEmpty == false else { return nil }

        let chrome = CGFloat(slots.count - 1) * (Layout.gap + Layout.dividerWidth)
        let usable = available - chrome
        let minimums = slots.map(\.widget.minWidth)
        let minimumTotal = minimums.reduce(0, +)
        guard usable >= minimumTotal else { return nil }

        var widths = minimums
        var slack = usable - minimumTotal

        // First grow everyone toward their ideal, proportionally to how far they are off.
        let deficits = slots.enumerated().map { max(0, $0.element.widget.idealWidth - widths[$0.offset]) }
        let deficitTotal = deficits.reduce(0, +)
        if deficitTotal > 0 {
            let share = min(1, slack / deficitTotal)
            for index in widths.indices {
                let bump = deficits[index] * share
                widths[index] += bump
                slack -= bump
            }
        }

        // Anything still left goes out by grow, exactly like flex-grow.
        if slack > 0.5 {
            let growTotal = slots.reduce(0) { $0 + $1.widget.grow }
            if growTotal > 0 {
                for index in widths.indices {
                    widths[index] += slack * (slots[index].widget.grow / growTotal)
                }
            }
        }

        return widths
    }

    private func rebuildDividers(count: Int) {
        while dividers.count > count {
            dividers.removeLast().removeFromSuperview()
        }
        while dividers.count < count {
            let divider = NSView()
            divider.wantsLayer = true
            divider.layer?.backgroundColor = Style.tertiaryText.withAlphaComponent(0.25).cgColor
            addSubview(divider)
            dividers.append(divider)
        }
    }

    // MARK: - Widget views

    private func makeView(for widget: PanelWidget, sizeClass: WidgetSizeClass) -> NSView {
        let compact = sizeClass != .regular

        switch widget {
        case .media:
            let view = MediaDetailView(isCompact: compact)
            view.onPlayPause = callbacks.onPlayPause
            view.onNextTrack = callbacks.onNextTrack
            view.onPreviousTrack = callbacks.onPreviousTrack
            view.onOpenSource = callbacks.onOpenSource
            view.onShuffle = callbacks.onShuffle
            view.onVolume = callbacks.onVolume
            view.onSeek = callbacks.onSeek
            return view

        case .playlists:
            let view = PlaylistsPaneView()
            view.onPlay = callbacks.onPlayURI
            return view

        case .tray:
            return TrayPaneView(isCompact: compact)

        case .apps:
            let view = AppsPaneView(isCompact: compact)
            view.onSelect = callbacks.onSelectShortcut
            return view

        case .shortcuts:
            return ShortcutsPaneView()

        case .timer:
            let view = TimerPaneView()
            view.onStart = callbacks.onStartTimer
            view.onCancel = callbacks.onCancelTimer
            return view

        case .calendar:
            let view = CalendarPaneView()
            view.reload()
            return view

        case .notifications:
            let view = NotificationsPaneView()
            view.reload()
            return view

        case .system:
            return SystemPaneView()

        case .mirror:
            return MirrorPaneView()

        case .notes:
            let view = NotesPaneView(isCompact: compact)
            view.onDismiss = callbacks.onDismiss
            return view

        case .clipboard:
            let view = ClipboardPaneView(isCompact: compact)
            view.onPaste = callbacks.onPasteClipboard
            view.onDismiss = callbacks.onDismiss
            return view
        }
    }

    private func views<T: NSView>(of type: T.Type) -> [T] {
        slots.compactMap { $0.view as? T }
    }

    // MARK: - Updates

    func render(_ state: NowPlayingState) {
        views(of: MediaDetailView.self).forEach { $0.render(state) }
        views(of: AppsPaneView.self).forEach { $0.refreshRunningStates() }
    }

    func updateTimer(remaining: TimeInterval) {
        views(of: TimerPaneView.self).forEach { $0.update(remaining: remaining) }
    }

    func refreshNotifications() {
        views(of: NotificationsPaneView.self).forEach { $0.reload() }
    }

    func reloadTray() {
        views(of: TrayPaneView.self).forEach { $0.reload() }
    }

    func startTracking() {
        views(of: SystemPaneView.self).forEach { $0.startTracking() }
    }

    func stopTracking() {
        views(of: SystemPaneView.self).forEach { $0.stopTracking() }
        views(of: MirrorPaneView.self).forEach { $0.stopIfNeeded() }
    }
}
