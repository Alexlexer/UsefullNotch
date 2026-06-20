import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notchPanelController: NotchPanelController?
    private var hoverController: NotchHoverController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "macbook",
            accessibilityDescription: "Useful Notch"
        )
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
    private let panel: NSPanel
    private let contentView = NotchPanelView()

    var isVisible: Bool {
        panel.isVisible
    }

    var frame: NSRect {
        panel.frame
    }

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 88),
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
        positionPanel()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else {
            return
        }

        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - panelSize.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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
    private let subtitleLabel = NSTextField(labelWithString: "Drag files here, pin quick notes, and launch tools.")
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.72)

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)

        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -22),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let background = NSBezierPath(roundedRect: bounds, xRadius: 24, yRadius: 24)
        NSColor(calibratedWhite: 0.05, alpha: 0.92).setFill()
        background.fill()

        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 23.5, yRadius: 23.5)
        NSColor.white.withAlphaComponent(0.12).setStroke()
        border.lineWidth = 1
        border.stroke()
    }
}
