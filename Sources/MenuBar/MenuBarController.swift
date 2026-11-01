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

        let label = PassthroughHostingView(rootView: AnyView(
            LiveStatusLabel(model: model) { [weak item] size in
                // 只按内容宽度设置，取整到整点；忽略重新布局时的瞬时值和不到 1pt 的变化，
                // 避免图标在多块显示器的菜单栏之间切换时宽度来回变化。
                guard let item, size.width >= 10 else { return }
                let length = max(22, size.width.rounded(.up))
                if abs(item.length - length) >= 1 { item.length = length }
            }
            .deadlinerTheme()
        ))
        // 不让 SwiftUI 的尺寸约束反过来影响菜单栏按钮的宽度（宽度只由 item.length 决定）。
        label.sizingOptions = []
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            label.topAnchor.constraint(equalTo: button.topAnchor),
            label.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        statusItem = item
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
        let hosting = NSHostingView(rootView: content)
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

/// 不拦截鼠标事件的 NSHostingView，让点击落到菜单栏按钮上。
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
