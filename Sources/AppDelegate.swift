import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panelController: PanelController?
    private let viewModel = PanelViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 没有 Dock 图标（LSUIElement 双保险）
        NSApp.setActivationPolicy(.accessory)

        let controller = PanelController(viewModel: viewModel)
        panelController = controller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "小板"
            button.imagePosition = .noImage
            button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            button.action = #selector(togglePanel)
            button.target = self
            button.toolTip = "azure桌面小板"
        }
        statusItem = item
    }

    @objc private func togglePanel() {
        guard let button = statusItem?.button else { return }
        panelController?.toggle(relativeTo: button)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 退出前把还没落盘的输入立刻写进 UserDefaults，防止最后 0.5 秒内打的字丢失
        viewModel.flushDraft()
    }
}
