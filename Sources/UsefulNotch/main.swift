import AppKit
import QuartzCore
import SwiftUI

enum NotchPresentationMode {
    case usefulPanel
    case siri
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notchPanelController: NotchPanelController?
    private var hoverController: NotchHoverController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let statusImage = NSImage(
            systemSymbolName: "macbook",
            accessibilityDescription: "Useful Notch"
        )
        statusItem.button?.image = statusImage
        statusItem.button?.title = statusImage == nil ? "UN" : ""
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        self.statusItem = statusItem

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show UsefulNotch", action: #selector(showUsefulPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Siri Animation", action: #selector(showSiriAnimation), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Hide", action: #selector(hidePanel), keyEquivalent: ""))
        menu.items.forEach { item in
            item.target = self
        }
        statusItem.menu = menu

        notchPanelController = NotchPanelController()
        if let notchPanelController {
            hoverController = NotchHoverController(panelController: notchPanelController)
            hoverController?.start()

            if ProcessInfo.processInfo.arguments.contains("--debug-siri-cycle") {
                notchPanelController.runSiriDebugCycle()
            }
        }
    }

    @objc private func statusItemClicked() {
        notchPanelController?.toggle()
    }

    @objc private func showUsefulPanel() {
        notchPanelController?.showUsefulPanel()
    }

    @objc private func showSiriAnimation() {
        notchPanelController?.showSiriAnimation()
    }

    @objc private func hidePanel() {
        notchPanelController?.hide()
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()

final class NotchPanelController {
    private let expandedPanelSize = NSSize(width: 560, height: 190)
    private let panel: NSPanel
    private let contentView = NotchPanelView()
    private let siriController = SiriNotchController()
    private let siriHostingView: NSHostingView<SiriNotchAnimationView>
    private var targetFrame = NSRect.zero
    private var isAnimating = false
    private var transitionGeneration = 0
    private var presentationMode: NotchPresentationMode = .usefulPanel

    var isVisible: Bool {
        panel.isVisible || isAnimating
    }

    var frame: NSRect {
        panel.frame
    }

    init() {
        let siriMetrics = SiriNotchMetrics.defaultMetrics()
        siriHostingView = NSHostingView(
            rootView: SiriNotchAnimationView(controller: siriController, metrics: siriMetrics)
        )
        siriHostingView.wantsLayer = true
        siriHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        siriHostingView.translatesAutoresizingMaskIntoConstraints = false
        siriHostingView.isHidden = true

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: expandedPanelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = contentView

        contentView.addSubview(siriHostingView)
        NSLayoutConstraint.activate([
            siriHostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            siriHostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            siriHostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            siriHostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    func show() {
        showUsefulPanel()
    }

    func showUsefulPanel() {
        transitionGeneration += 1
        presentationMode = .usefulPanel
        siriController.dismiss()
        contentView.setUsefulContentVisible(true)
        siriHostingView.isHidden = true

        guard !panel.isVisible else {
            contentView.startAnimation()
            return
        }

        isAnimating = true
        targetFrame = positionedPanelFrame()
        panel.setFrame(collapsedPillFrame(from: targetFrame), display: false)
        panel.alphaValue = 0
        contentView.prepareForReveal()
        panel.orderFrontRegardless()
        Haptics.panelOpened()
        contentView.startAnimation()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.90, 0.22, 1.0)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            self?.isAnimating = false
        }
        contentView.revealContent()
    }

    func hide() {
        guard panel.isVisible || isAnimating else {
            return
        }

        transitionGeneration += 1
        let generation = transitionGeneration
        isAnimating = true

        let expandedFrame = targetFrame == .zero ? positionedPanelFrame() : targetFrame
        let hiddenFrame = collapsedPillFrame(from: expandedFrame)
        contentView.prepareForReveal()
        contentView.stopAnimation()
        if presentationMode == .siri {
            siriController.dismiss()
        }
        panel.setFrame(expandedFrame, display: false)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0.0, 0.85, 0.35)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(hiddenFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self, self.transitionGeneration == generation else {
                return
            }
            self.panel.orderOut(nil)
            self.siriHostingView.isHidden = true
            self.contentView.setUsefulContentVisible(true)
            self.presentationMode = .usefulPanel
            self.isAnimating = false
        }
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func showSiriAnimation() {
        transitionGeneration += 1
        presentationMode = .siri

        if !panel.isVisible {
            targetFrame = positionedPanelFrame()
            panel.setFrame(targetFrame, display: false)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }

        contentView.stopAnimation()
        contentView.setUsefulContentVisible(false)
        siriHostingView.isHidden = false
        siriController.activate()
    }

    func runSiriDebugCycle() {
        transitionGeneration += 1
        presentationMode = .siri
        targetFrame = positionedPanelFrame()
        panel.setFrame(targetFrame, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        contentView.stopAnimation()
        contentView.setUsefulContentVisible(false)
        siriHostingView.isHidden = false
        siriController.runDebugCycle()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.25) { [weak self] in
            guard let self else {
                return
            }
            self.presentationMode = .usefulPanel
            self.siriHostingView.isHidden = true
            self.contentView.setUsefulContentVisible(true)
            self.contentView.startAnimation()
        }
    }

    private func positionedPanelFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return panel.frame
        }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - expandedPanelSize.width / 2
        let y = screenFrame.maxY - expandedPanelSize.height - 8
        return NSRect(origin: NSPoint(x: x, y: y), size: expandedPanelSize)
    }

    private func collapsedPillFrame(from frame: NSRect) -> NSRect {
        NSRect(
            x: frame.midX - 132,
            y: frame.maxY - 42,
            width: 264,
            height: 42
        )
    }
}

final class NotchHoverController {
    private let panelController: NotchPanelController
    private var hoverTimer: Timer?
    private var hideTimer: Timer?

    private let triggerWidth: CGFloat = 260
    private let triggerHeight: CGFloat = 42
    private let panelGraceArea: CGFloat = 18
    private let hideDelay: TimeInterval = 0.45

    init(panelController: NotchPanelController) {
        self.panelController = panelController
    }

    func start() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(
            withTimeInterval: 0.08,
            repeats: true
        ) { [weak self] _ in
            self?.update()
        }
    }

    private func update() {
        let mouseLocation = NSEvent.mouseLocation

        if isInNotchTrigger(mouseLocation) || isInPanelGraceArea(mouseLocation) {
            hideTimer?.invalidate()
            hideTimer = nil

            if !panelController.isVisible {
                panelController.show()
            }
            return
        }

        scheduleHideIfNeeded()
    }

    private func scheduleHideIfNeeded() {
        guard panelController.isVisible, hideTimer == nil else {
            return
        }

        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { [weak self] _ in
            self?.panelController.hide()
            self?.hideTimer = nil
        }
    }

    private func isInNotchTrigger(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return false
        }

        let screenFrame = screen.frame
        let triggerRect = NSRect(
            x: screenFrame.midX - triggerWidth / 2,
            y: screenFrame.maxY - triggerHeight,
            width: triggerWidth,
            height: triggerHeight
        )

        return triggerRect.contains(point)
    }

    private func isInPanelGraceArea(_ point: NSPoint) -> Bool {
        guard panelController.isVisible else {
            return false
        }

        return panelController.frame.insetBy(dx: -panelGraceArea, dy: -panelGraceArea).contains(point)
    }
}

final class NotchGlassEffectView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        isEmphasized = false
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class NotchPanelView: NSView {
    private let glassView = NotchGlassEffectView()
    private let titleLabel = NSTextField(labelWithString: "Useful Notch")
    private let glowView = AmbientGlowView()
    private let headerStackView = NSStackView()
    private let subtitleLabel = NSTextField(labelWithString: "Drop files here to keep them close.")
    private let tabControl = NSSegmentedControl(labels: ["Shelf", "Calendar"], trackingMode: .selectOne, target: nil, action: nil)
    private let contentContainer = NSView()
    private let shelfView = NSView()
    private let fileStackView = NSStackView()
    private let calendarView = CalendarMonthView()
    private var fileURLs: [URL] = []
    private var isDropTargeted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])

        glassView.translatesAutoresizingMaskIntoConstraints = false
        glowView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.72)

        headerStackView.orientation = .vertical
        headerStackView.alignment = .leading
        headerStackView.spacing = 4
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        headerStackView.addArrangedSubview(titleLabel)
        headerStackView.addArrangedSubview(subtitleLabel)

        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(tabChanged)
        tabControl.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        shelfView.translatesAutoresizingMaskIntoConstraints = false
        calendarView.translatesAutoresizingMaskIntoConstraints = false
        fileStackView.orientation = .horizontal
        fileStackView.alignment = .centerY
        fileStackView.spacing = 8
        fileStackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glassView)
        addSubview(glowView)
        addSubview(headerStackView)
        addSubview(tabControl)
        addSubview(contentContainer)

        contentContainer.addSubview(shelfView)
        contentContainer.addSubview(calendarView)
        shelfView.addSubview(fileStackView)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            glowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glowView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glowView.topAnchor.constraint(equalTo: topAnchor),
            glowView.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            headerStackView.trailingAnchor.constraint(lessThanOrEqualTo: tabControl.leadingAnchor, constant: -16),
            headerStackView.topAnchor.constraint(equalTo: topAnchor, constant: 18),

            tabControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            tabControl.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            tabControl.widthAnchor.constraint(equalToConstant: 168),

            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            contentContainer.topAnchor.constraint(equalTo: headerStackView.bottomAnchor, constant: 14),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),

            shelfView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            shelfView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            shelfView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            shelfView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            calendarView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            calendarView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            calendarView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            calendarView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            fileStackView.leadingAnchor.constraint(equalTo: shelfView.leadingAnchor),
            fileStackView.trailingAnchor.constraint(lessThanOrEqualTo: shelfView.trailingAnchor),
            fileStackView.centerYAnchor.constraint(equalTo: shelfView.centerYAnchor),
            fileStackView.heightAnchor.constraint(equalToConstant: 28)
        ])

        calendarView.isHidden = true
        updateFileShelf()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func prepareForReveal() {
        headerStackView.alphaValue = 0
        tabControl.alphaValue = 0
        contentContainer.alphaValue = 0
        glowView.alphaValue = 0
    }

    func startAnimation() {
        glowView.startAnimation()
    }

    func stopAnimation() {
        glowView.stopAnimation()
    }

    func setUsefulContentVisible(_ isVisible: Bool) {
        headerStackView.isHidden = !isVisible
        tabControl.isHidden = !isVisible
        contentContainer.isHidden = !isVisible
        glowView.isHidden = !isVisible
    }

    func revealContent() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            glowView.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let self else {
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.allowsImplicitAnimation = true
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.headerStackView.animator().alphaValue = 1
                self.tabControl.animator().alphaValue = 1
                self.contentContainer.animator().alphaValue = 1
            }
        }
    }

    @objc private func tabChanged() {
        let showsCalendar = tabControl.selectedSegment == 1
        shelfView.isHidden = showsCalendar
        calendarView.isHidden = !showsCalendar
        subtitleLabel.stringValue = showsCalendar
            ? "Your month at a glance."
            : "Drop files here to keep them close."
        Haptics.tabChanged()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSBezierPath(roundedRect: bounds, xRadius: 24, yRadius: 24)
        NSGraphicsContext.saveGraphicsState()
        background.addClip()

        let surfaceGradient = NSGradient(colors: [
            NSColor.black.withAlphaComponent(isDropTargeted ? 0.38 : 0.34),
            NSColor.black.withAlphaComponent(isDropTargeted ? 0.58 : 0.52)
        ])
        surfaceGradient?.draw(in: bounds, angle: -90)

        let lowerReflection = NSGradient(colors: [
            .clear,
            NSColor(calibratedRed: 0.082, green: 0.082, blue: 0.102, alpha: 0.12),
            .clear
        ])
        lowerReflection?.draw(in: bounds.insetBy(dx: 0, dy: bounds.height * 0.18), angle: -90)

        NSGraphicsContext.restoreGraphicsState()

        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 23.5, yRadius: 23.5)
        let borderColor = isDropTargeted
            ? NSColor(calibratedRed: 0.10, green: 0.90, blue: 1.00, alpha: 0.42)
            : NSColor.white.withAlphaComponent(0.06)
        borderColor.setStroke()
        border.lineWidth = 1
        border.stroke()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFileURLs(sender) else {
            return []
        }

        isDropTargeted = true
        glowView.isDropTargeted = true
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
        glowView.isDropTargeted = false
        needsDisplay = true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTargeted = false
        glowView.isDropTargeted = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let droppedURLs = fileURLs(from: sender)
        guard !droppedURLs.isEmpty else {
            return false
        }

        fileURLs = Array((droppedURLs + fileURLs).uniqued().prefix(4))
        updateFileShelf()
        Haptics.filesAdded()

        isDropTargeted = false
        glowView.isDropTargeted = false
        needsDisplay = true
        return true
    }

    private func hasFileURLs(_ sender: NSDraggingInfo) -> Bool {
        !fileURLs(from: sender).isEmpty
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }

    private func updateFileShelf() {
        fileStackView.arrangedSubviews.forEach { view in
            fileStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if fileURLs.isEmpty {
            fileStackView.addArrangedSubview(makeHintLabel())
            return
        }

        fileURLs.forEach { url in
            fileStackView.addArrangedSubview(FileChipView(fileURL: url))
        }
    }

    private func makeHintLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "No files yet")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.42)
        return label
    }
}

enum Haptics {
    static func panelOpened() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }

    static func filesAdded() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .now
        )
    }

    static func tabChanged() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }
}

final class CalendarMonthView: NSView {
    private let monthLabel = NSTextField(labelWithString: "")
    private let gridStackView = NSStackView()
    private let calendar = Calendar.current
    private let today = Date()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        monthLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        monthLabel.textColor = .white
        monthLabel.translatesAutoresizingMaskIntoConstraints = false

        gridStackView.orientation = .vertical
        gridStackView.alignment = .leading
        gridStackView.spacing = 3
        gridStackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(monthLabel)
        addSubview(gridStackView)

        NSLayoutConstraint.activate([
            monthLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            monthLabel.topAnchor.constraint(equalTo: topAnchor),

            gridStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            gridStackView.topAnchor.constraint(equalTo: monthLabel.bottomAnchor, constant: 6),
            gridStackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        buildCalendar()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildCalendar() {
        monthLabel.stringValue = monthTitle(for: today)

        gridStackView.addArrangedSubview(makeWeekdayRow())

        let days = daysForVisibleMonth()
        stride(from: 0, to: days.count, by: 7).forEach { index in
            let week = Array(days[index..<min(index + 7, days.count)])
            gridStackView.addArrangedSubview(makeDayRow(days: week))
        }
    }

    private func makeWeekdayRow() -> NSStackView {
        let row = makeRow()
        weekdaySymbols().forEach { symbol in
            let label = makeCellLabel(symbol.uppercased(), color: NSColor.white.withAlphaComponent(0.42), weight: .semibold)
            row.addArrangedSubview(label)
        }
        return row
    }

    private func makeDayRow(days: [CalendarDay]) -> NSStackView {
        let row = makeRow()
        days.forEach { day in
            row.addArrangedSubview(CalendarDayCell(day: day))
        }
        return row
    }

    private func makeRow() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeCellLabel(_ text: String, color: NSColor, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 9, weight: weight)
        label.textColor = color
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 24),
            label.heightAnchor.constraint(equalToConstant: 14)
        ])

        return label
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale.current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    private func weekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        guard symbols.count == 7 else {
            return ["S", "M", "T", "W", "T", "F", "S"]
        }

        let firstWeekdayIndex = calendar.firstWeekday - 1
        return Array(symbols[firstWeekdayIndex...] + symbols[..<firstWeekdayIndex]).map { String($0.prefix(1)) }
    }

    private func daysForVisibleMonth() -> [CalendarDay] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: today),
            let monthRange = calendar.range(of: .day, in: .month, for: today),
            let firstMonthWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else {
            return []
        }

        let numberOfWeeks = Int(ceil(Double(monthRange.count + leadingBlankCount(firstMonthWeek.start, monthInterval.start)) / 7.0))
        let visibleDayCount = max(numberOfWeeks, 5) * 7

        return (0..<visibleDayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstMonthWeek.start) else {
                return nil
            }

            return CalendarDay(
                number: calendar.component(.day, from: date),
                isInCurrentMonth: calendar.isDate(date, equalTo: today, toGranularity: .month),
                isToday: calendar.isDateInToday(date)
            )
        }
    }

    private func leadingBlankCount(_ gridStart: Date, _ monthStart: Date) -> Int {
        calendar.dateComponents([.day], from: gridStart, to: monthStart).day ?? 0
    }
}

struct CalendarDay {
    let number: Int
    let isInCurrentMonth: Bool
    let isToday: Bool
}

final class CalendarDayCell: NSView {
    init(day: CalendarDay) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        layer?.cornerRadius = 7
        layer?.backgroundColor = day.isToday
            ? NSColor.systemBlue.withAlphaComponent(0.86).cgColor
            : NSColor.clear.cgColor

        let label = NSTextField(labelWithString: String(day.number))
        label.font = .systemFont(ofSize: 10, weight: day.isToday ? .bold : .medium)
        label.textColor = day.isInCurrentMonth
            ? .white
            : NSColor.white.withAlphaComponent(0.28)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class AmbientGlowView: NSView {
    var isDropTargeted = false {
        didSet {
            needsDisplay = true
        }
    }

    private var phase: CGFloat = 0
    private var animationTimer: Timer?
    private var lastFrameTime: TimeInterval?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopAnimation()
        }
    }

    func startAnimation() {
        guard animationTimer == nil else {
            return
        }

        lastFrameTime = CACurrentMediaTime()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 45.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        lastFrameTime = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let deltaTime = now - (lastFrameTime ?? now)
        lastFrameTime = now
        phase += CGFloat(deltaTime) * 2.4
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let clippingPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 23, yRadius: 23)
        clippingPath.addClip()

        NSColor.clear.setFill()
        bounds.fill()

        let ribbonRect = NSRect(
            x: bounds.midX - bounds.width * 0.29,
            y: bounds.midY - 19,
            width: bounds.width * 0.58,
            height: 38
        )
        drawAmbientWave(in: ribbonRect, alpha: isDropTargeted ? 0.34 : 0.26)
        drawBrightWave(in: ribbonRect.insetBy(dx: 0, dy: 13), alpha: isDropTargeted ? 0.68 : 0.52)
        drawReflection(in: ribbonRect)

        drawGlow(
            color: NSColor(calibratedRed: 0.10, green: 0.90, blue: 1.00, alpha: 1.0),
            center: NSPoint(x: bounds.midX + sin(phase * 0.43) * bounds.width * 0.09, y: ribbonRect.midY + 4),
            radius: 54
        )
        drawGlow(
            color: NSColor(calibratedRed: 0.42, green: 0.18, blue: 1.00, alpha: 1.0),
            center: NSPoint(x: bounds.midX + cos(phase * 0.31) * bounds.width * 0.08, y: ribbonRect.midY - 2),
            radius: 48
        )
        drawGlow(
            color: NSColor(calibratedRed: 1.00, green: 0.10, blue: 0.65, alpha: 1.0),
            center: NSPoint(x: bounds.midX + sin(phase * 0.37 + 1.2) * bounds.width * 0.10, y: ribbonRect.midY + 2),
            radius: 42
        )

        if isDropTargeted {
            drawGlow(
                color: NSColor(calibratedRed: 0.92, green: 0.98, blue: 1.00, alpha: 1.0),
                center: NSPoint(x: bounds.midX, y: bounds.midY),
                radius: 86
            )
        }
    }

    private func drawAmbientWave(in rect: NSRect, alpha: CGFloat) {
        drawWave(in: rect, lineWidth: 28, alpha: alpha, blurRadius: 0)
    }

    private func drawBrightWave(in rect: NSRect, alpha: CGFloat) {
        drawWave(in: rect, lineWidth: 9, alpha: alpha, blurRadius: 0)
        drawWave(in: rect.insetBy(dx: rect.width * 0.28, dy: 2), lineWidth: 3, alpha: min(0.65, alpha + 0.10), blurRadius: 0)
    }

    private func drawReflection(in rect: NSRect) {
        let width = bounds.width * 0.45
        let x = bounds.midX - width / 2 + sin(phase * 0.18) * bounds.width * 0.10
        let reflectionRect = NSRect(x: x, y: rect.midY + 14, width: width, height: 5)
        let path = NSBezierPath(roundedRect: reflectionRect, xRadius: 2.5, yRadius: 2.5)
        NSColor.white.withAlphaComponent(0.05).setFill()
        path.fill()
    }

    private func drawWave(in rect: NSRect, lineWidth: CGFloat, alpha: CGFloat, blurRadius: CGFloat) {
        let points = wavePoints(in: rect)
        guard points.count > 1 else {
            return
        }

        for index in 1..<points.count {
            let progress = CGFloat(index) / CGFloat(points.count - 1)
            let segment = NSBezierPath()
            segment.move(to: points[index - 1])
            segment.line(to: points[index])
            segment.lineWidth = lineWidth
            segment.lineCapStyle = .round
            segment.lineJoinStyle = .round
            color(at: progress, alpha: alpha).setStroke()
            segment.stroke()
        }
    }

    private func wavePoints(in rect: NSRect) -> [NSPoint] {
        let pointCount = 64
        var points: [NSPoint] = []
        points.reserveCapacity(pointCount)

        for index in 0..<pointCount {
            let progress = CGFloat(index) / CGFloat(pointCount - 1)
            let x = rect.minX + progress * rect.width
            let normalizedX = progress
            let y = rect.midY
                + sin(normalizedX * .pi * 2 + phase) * 5
                + sin(normalizedX * .pi * 4 - phase * 0.65) * 2
                + sin(normalizedX * .pi * 7 + phase * 0.35) * 1
            points.append(NSPoint(x: x, y: y))
        }

        return points
    }

    private func color(at position: CGFloat, alpha: CGFloat) -> NSColor {
        let cyanPosition = 0.18 + sin(phase * 0.43) * 0.08
        let violetPosition = 0.48 + cos(phase * 0.31) * 0.07
        let magentaPosition = 0.70 + sin(phase * 0.37 + 1.2) * 0.08
        let warmPosition = 0.84 + sin(phase * 0.61 + 0.5) * 0.10

        let cyan = gaussian(position, center: cyanPosition, width: 0.18)
        let blue = gaussian(position, center: 0.34 + sin(phase * 0.27) * 0.05, width: 0.20)
        let violet = gaussian(position, center: violetPosition, width: 0.16)
        let magenta = gaussian(position, center: magentaPosition, width: 0.12) * 0.44
        let warm = gaussian(position, center: warmPosition, width: 0.08) * 0.20
        let white = gaussian(position, center: cyanPosition + 0.08, width: 0.07) * 0.62

        let red = 0.10 * cyan + 0.08 * blue + 0.42 * violet + 1.00 * magenta + 1.00 * warm + 0.92 * white
        let green = 0.90 * cyan + 0.42 * blue + 0.18 * violet + 0.10 * magenta + 0.48 * warm + 0.98 * white
        let blueChannel = 1.00 * cyan + 1.00 * blue + 1.00 * violet + 0.65 * magenta + 0.08 * warm + 1.00 * white
        let total = max(0.22, cyan + blue + violet + magenta + warm + white)

        return NSColor(
            calibratedRed: min(red / total, 1),
            green: min(green / total, 1),
            blue: min(blueChannel / total, 1),
            alpha: alpha
        )
    }

    private func gaussian(_ x: CGFloat, center: CGFloat, width: CGFloat) -> CGFloat {
        let distance = (x - center) / width
        return exp(-distance * distance)
    }

    private func drawGlow(color: NSColor, center: NSPoint, radius: CGFloat) {
        let alpha: CGFloat = isDropTargeted ? 0.18 : 0.10
        let gradient = NSGradient(colors: [
            color.withAlphaComponent(alpha),
            color.withAlphaComponent(alpha * 0.20),
            .clear
        ])

        gradient?.draw(
            fromCenter: center,
            radius: 0,
            toCenter: center,
            radius: radius,
            options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
        )
    }
}

final class FileChipView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    init(fileURL: URL) {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor

        translatesAutoresizingMaskIntoConstraints = false

        iconView.image = NSWorkspace.shared.icon(forFile: fileURL.path)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = fileURL.lastPathComponent
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            widthAnchor.constraint(lessThanOrEqualToConstant: 142),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

extension Array where Element == URL {
    func uniqued() -> [URL] {
        var seen = Set<URL>()
        return filter { seen.insert($0).inserted }
    }
}
