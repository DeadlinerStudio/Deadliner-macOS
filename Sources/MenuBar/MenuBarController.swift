import AppKit
import SwiftUI

/// 菜单栏项目：系统的 NSStatusItem + 自绘内容（系统 MenuBarExtra 只能显示图标和一行文字），
/// 点击后在下方弹出无边框的浮动面板。点面板外、按 Esc 或再次点击图标时关闭。
@MainActor
final class MenuBarController: NSObject {
    private let model: AppModel
    private let openMainWindow: () -> Void
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?
    private var insideClickMonitor: Any?
    private var activationObservers: [NSObjectProtocol] = []
    private var defaultsObserver: NSObjectProtocol?

    init(model: AppModel, openMainWindow: @escaping () -> Void) {
        self.model = model
        self.openMainWindow = openMainWindow
        super.init()
        UserDefaults.standard.register(defaults: [MenuBarSettings.enabledKey: true])
        applyEnabled()
        // 设置中开关菜单栏图标后立即生效。
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyEnabled() }
        }
    }

    func tearDown() {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        closePanel()
        removeStatusItem()
    }

    private func applyEnabled() {
        if UserDefaults.standard.bool(forKey: MenuBarSettings.enabledKey) {
            if statusItem == nil { installStatusItem() }
        } else {
            closePanel()
            removeStatusItem()
        }
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(togglePanel)
        button.setAccessibilityLabel("Deadliner")

        Self.attachLabel(AnyView(LiveStatusLabel(model: model).deadlinerTheme()), to: item)
        statusItem = item
    }

    /// 把 SwiftUI 内容放进菜单栏按钮。嵌入视图只报告内容本身的尺寸，在按钮中居中；
    /// 按钮宽度（`item.length`）在内容尺寸变化时设为内容宽度。嵌入视图不约束按钮的宽度，
    /// 否则非活动显示器上的菜单栏副本宽度会和活动屏幕不同。
    static func attachLabel(_ content: AnyView, to item: NSStatusItem) {
        guard let button = item.button else { return }
        let label = PassthroughHostingView(rootView: AnyView(content.fixedSize()))
        label.sizingOptions = [.intrinsicContentSize]
        label.onIntrinsicSizeChange = { [weak item] size in
            // 取整到整点；忽略瞬时的过小值和不到 1pt 的变化。
            guard let item, size.width >= 10 else { return }
            let length = max(22, size.width.rounded(.up))
            if abs(item.length - length) >= 1 { item.length = length }
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        label.reportIntrinsicSize()
    }

    private func removeStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if panel?.isVisible == true { closePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }
        model.prepareMenuBarPanel()

        let content = MenuBarPanel(
            model: model,
            close: { [weak self] in self?.closePanel() },
            openMain: { [weak self] in
                self?.closePanel()
                self?.openMainWindow()
            }
        )
        .deadlinerTheme()
        let hosting = PanelHostingView(rootView: content)
        let size = hosting.fittingSize
        let width = max(320, size.width)
        let height = max(200, size.height)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        // 定位到图标正下方，并保持在屏幕内。
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var origin = NSPoint(x: buttonFrame.midX - width / 2, y: buttonFrame.minY - height - 6)
        origin.x = min(max(origin.x, screenFrame.minX + 8), screenFrame.maxX - width - 8)
        panel.setFrameOrigin(origin)
        // 内容高度变化（例如面板打开时开始或结束专注）时，窗口跟着变，上边缘保持贴着菜单栏。
        hosting.onFittingSizeChange = { [weak panel] size in
            guard let panel else { return }
            var frame = panel.frame
            let top = frame.maxY
            frame.size.height = max(200, size.height)
            frame.origin.y = top - frame.size.height
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
        // 本应用其他窗口里的点击不会进入全局监听，另外用本地监听判断（面板与菜单栏图标自身除外）。
        insideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let window = event.window else { return }
                if window !== self.panel && window !== self.statusItem?.button?.window { self.closePanel() }
            }
            return event
        }
        let center = NSWorkspace.shared.notificationCenter
        activationObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closePanel() }
            },
        ]
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            MainActor.assumeIsolated { self?.closePanel() }
            return nil
        }
    }

    func closePanel() {
        panel?.orderOut(nil)
        panel = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let insideClickMonitor { NSEvent.removeMonitor(insideClickMonitor) }
        outsideClickMonitor = nil
        escapeMonitor = nil
        insideClickMonitor = nil
        activationObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        activationObservers = []
    }
}

/// 面板的 NSHostingView：SwiftUI 内容尺寸变化时通知控制器调整窗口。
private final class PanelHostingView<Content: View>: NSHostingView<Content> {
    var onFittingSizeChange: ((CGSize) -> Void)?
    private var lastHeight: CGFloat = 0

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let size = self.fittingSize
            guard abs(size.height - self.lastHeight) > 0.5 else { return }
            self.lastHeight = size.height
            self.onFittingSizeChange?(size)
        }
    }
}

/// 不拦截鼠标事件的 NSHostingView，让点击落到菜单栏按钮上。
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var onIntrinsicSizeChange: ((CGSize) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // SwiftUI 内容变化（数字位数、样式）时会走到这里；下一轮再读取，拿到更新后的尺寸。
        DispatchQueue.main.async { [weak self] in self?.reportIntrinsicSize() }
    }

    func reportIntrinsicSize() {
        onIntrinsicSizeChange?(intrinsicContentSize)
    }
}
