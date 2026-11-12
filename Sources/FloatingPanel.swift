import AppKit
import SwiftUI

/// 无边框、能成为 key window 的悬浮面板。
/// nonactivatingPanel：弹出时不抢当前 App 的焦点，但输入框照样能打字。
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PanelController: NSObject, NSWindowDelegate {
    private let panel: KeyablePanel
    private let viewModel: PanelViewModel
    private var lastHideDate = Date.distantPast
    private var suppressHide = false

    /// 面板可拉伸的范围
    private static let minSize = NSSize(width: 280, height: 226)
    private static let maxSize = NSSize(width: 520, height: 700)

    /// 上次拉伸后的尺寸（UserDefaults 记住，没有就用默认值）
    private static func savedPanelSize() -> NSSize {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: "AzurePanel_PanelWidth")
        let height = defaults.double(forKey: "AzurePanel_PanelHeight")
        let w = width > 0 ? min(max(width, minSize.width), maxSize.width) : minSize.width
        let h = height > 0 ? min(max(height, minSize.height), maxSize.height) : minSize.height
        return NSSize(width: w, height: h)
    }

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: Self.savedPanelSize()),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentMinSize = Self.minSize
        panel.contentMaxSize = Self.maxSize
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: PanelContentView(vm: viewModel)
        )

        // 打开齿轮菜单（NSMenu）期间不要因为失焦把面板藏起来
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuTrackingBegan),
            name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuTrackingEnded),
            name: NSMenu.didEndTrackingNotification, object: nil)
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if panel.isVisible {
            hide()
        } else {
            // 刚刚因为点了菜单栏按钮而自动隐藏的话，这次点击就当作“关闭”处理
            guard Date().timeIntervalSince(lastHideDate) > 0.3 else { return }
            positionPanel(relativeTo: button)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) {
        guard let statusWindow = button.window else { return }
        let buttonFrame = statusWindow.convertToScreen(button.bounds)
        let size = panel.frame.size
        let x = max(8, buttonFrame.midX - size.width / 2)
        let y = buttonFrame.minY - size.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func hide() {
        viewModel.flushDraft()
        panel.orderOut(nil)
        lastHideDate = Date()
    }

    @objc private func menuTrackingBegan() {
        suppressHide = true
    }

    @objc private func menuTrackingEnded() {
        suppressHide = false
        viewModel.flushDraft()
        // 菜单打开期间窗口可能已经失去 key，重新拿回来，保证后续失焦能正常隐藏
        if panel.isVisible && !panel.isKeyWindow {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard !suppressHide else { return }
        viewModel.flushDraft()
        panel.orderOut(nil)
        lastHideDate = Date()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        // 拉伸结束后记住新尺寸，下次打开沿用
        let size = panel.frame.size
        UserDefaults.standard.set(size.width, forKey: "AzurePanel_PanelWidth")
        UserDefaults.standard.set(size.height, forKey: "AzurePanel_PanelHeight")
    }
}
