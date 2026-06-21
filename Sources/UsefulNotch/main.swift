import AppKit
import QuartzCore

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
        statusItem.button?.action = #selector(togglePanel)
        self.statusItem = statusItem

        notchPanelController = NotchPanelController()
        if let notchPanelController {
            hoverController = NotchHoverController(panelController: notchPanelController)
            hoverController?.start()
        }
    }

    @objc private func togglePanel() {
        notchPanelController?.toggle()
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
    private var targetFrame = NSRect.zero
    private var isAnimating = false

    var isVisible: Bool {
        panel.isVisible || isAnimating
    }

    var frame: NSRect {
        panel.frame
    }

    init() {
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
    }

    func show() {
        guard !panel.isVisible else {
            return
        }

        isAnimating = true
        targetFrame = positionedPanelFrame()
        panel.setFrame(startFrame(from: targetFrame), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        contentView.startAmbientAnimation()
        Haptics.panelOpened()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            self?.isAnimating = false
        }
    }

    func hide() {
        guard panel.isVisible else {
            return
        }

        let expandedFrame = targetFrame == .zero ? positionedPanelFrame() : targetFrame
        let hiddenFrame = startFrame(from: expandedFrame)
        isAnimating = true

        panel.setFrame(expandedFrame, display: false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(hiddenFrame, display: true)
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.contentView.stopAmbientAnimation()
            self?.isAnimating = false
        }
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
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

    private func startFrame(from frame: NSRect) -> NSRect {
        frame.offsetBy(dx: 0, dy: 18).insetBy(dx: 18, dy: 8)
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

final class NotchPanelView: NSView {
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

        addSubview(glowView)
        addSubview(headerStackView)
        addSubview(tabControl)
        addSubview(contentContainer)

        contentContainer.addSubview(shelfView)
        contentContainer.addSubview(calendarView)
        shelfView.addSubview(fileStackView)

        NSLayoutConstraint.activate([
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

    func startAmbientAnimation() {
        glowView.start()
    }

    func stopAmbientAnimation() {
        glowView.stop()
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
        let fillColor = isDropTargeted
            ? NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.14, alpha: 0.96)
            : NSColor(calibratedWhite: 0.04, alpha: 0.84)
        fillColor.setFill()
        background.fill()

        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 23.5, yRadius: 23.5)
        let borderColor = isDropTargeted
            ? NSColor.systemMint.withAlphaComponent(0.75)
            : NSColor.white.withAlphaComponent(0.12)
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

    private var timer: Timer?
    private var phase: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    func start() {
        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }

            phase += 0.024
            needsDisplay = true
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let clippingPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 23, yRadius: 23)
        clippingPath.addClip()

        NSColor.clear.setFill()
        bounds.fill()

        drawGlow(
            color: NSColor.systemBlue,
            center: animatedPoint(baseX: 0.28, baseY: 0.55, xWave: 0.09, yWave: 0.18, offset: 0),
            radius: 190
        )
        drawGlow(
            color: NSColor.systemPink,
            center: animatedPoint(baseX: 0.70, baseY: 0.50, xWave: 0.11, yWave: 0.16, offset: 1.6),
            radius: 170
        )
        drawGlow(
            color: NSColor.systemTeal,
            center: animatedPoint(baseX: 0.50, baseY: 0.35, xWave: 0.16, yWave: 0.10, offset: 3.1),
            radius: 160
        )

        if isDropTargeted {
            drawGlow(
                color: NSColor.systemMint,
                center: NSPoint(x: bounds.midX, y: bounds.midY),
                radius: 220
            )
        }
    }

    private func animatedPoint(
        baseX: CGFloat,
        baseY: CGFloat,
        xWave: CGFloat,
        yWave: CGFloat,
        offset: CGFloat
    ) -> NSPoint {
        NSPoint(
            x: bounds.width * (baseX + sin(phase + offset) * xWave),
            y: bounds.height * (baseY + cos(phase * 0.8 + offset) * yWave)
        )
    }

    private func drawGlow(color: NSColor, center: NSPoint, radius: CGFloat) {
        let alpha: CGFloat = isDropTargeted ? 0.38 : 0.24
        let gradient = NSGradient(colors: [
            color.withAlphaComponent(alpha),
            color.withAlphaComponent(alpha * 0.32),
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
