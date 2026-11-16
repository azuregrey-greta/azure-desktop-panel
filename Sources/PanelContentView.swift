import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class PanelViewModel: ObservableObject {
    enum SaveState: Equatable {
        case idle
        case saving
        case success
        case failure(String)
    }

    @Published var text: String {
        didSet { scheduleDebounceSave() }
    }
    @Published private(set) var saveState: SaveState = .idle
    @Published private(set) var draftPending = false
    @Published private(set) var draftSavedAt: Date?
    @Published private(set) var suggestionVisible = false
    /// 粘贴/OCR 的临时提示，2.5 秒后由输入框自动清空
    @Published private(set) var ocrHint: String?
    @Published private(set) var launchAtLogin: Bool

    /// 保存成功后面板自动收起的回调，由 PanelController 注入
    var onRequestClose: (() -> Void)?

    private let store = DraftStore()
    private let saver = NotesSaver()
    private var debounceCancellable: AnyCancellable?
    private let debounceInterval: TimeInterval = 0.5

    init() {
        // 启动时先恢复上次未保存的草稿（初始化期间的赋值不会触发 didSet）
        text = store.loadDraft()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var isSaving: Bool { saveState == .saving }

    func setSuggestionVisible(_ visible: Bool) {
        guard suggestionVisible != visible else { return }
        suggestionVisible = visible
    }

    func setOCRHint(_ message: String?) {
        guard ocrHint != message else { return }
        ocrHint = message
    }

    /// 防抖 0.5 秒后把输入写入 UserDefaults
    private func scheduleDebounceSave() {
        draftPending = true
        debounceCancellable?.cancel()
        let value = text
        debounceCancellable = Just(value)
            .delay(for: .seconds(debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.store.saveDraft(value)
                self.draftPending = false
                self.draftSavedAt = value.isEmpty ? nil : Date()
            }
    }

    /// 立刻把当前输入落盘（面板收起 / 保存前 / 退出前调用）
    func flushDraft() {
        debounceCancellable?.cancel()
        debounceCancellable = nil
        store.saveDraft(text)
        draftPending = false
        draftSavedAt = text.isEmpty ? nil : Date()
    }

    func clearAll() {
        debounceCancellable?.cancel()
        debounceCancellable = nil
        store.clearDraft()
        text = ""
        draftPending = false
        saveState = .idle
    }

    func save() {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            saveState = .failure("没有可保存的内容")
            return
        }
        // 保存前先把当前输入立刻落盘：即使写入失败，草稿也一点不丢
        flushDraft()
        saveState = .saving
        saver.append(content) { [weak self] errorMessage in
            guard let self else { return }
            if let errorMessage {
                // 写入失败：草稿原样保留，可以重试
                self.saveState = .failure(errorMessage)
            } else {
                // 写成功才清空 UserDefaults 草稿和输入框
                self.store.clearDraft()
                self.text = ""
                self.saveState = .success
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                    guard let self, self.text.isEmpty, self.saveState == .success else { return }
                    self.onRequestClose?()
                }
            }
        }
    }

    func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
            }
        } catch {
            // 注册失败不中断界面，状态以下一次读取为准
        }
        launchAtLogin = service.status == .enabled
    }

    func openNotesApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
    }
}

struct PanelContentView: View {
    @ObservedObject var vm: PanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            CalcTextView(vm: vm)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxHeight: .infinity)
                .background(Color.editorBackground)
            Divider()
            footer
        }
        .frame(minWidth: 280, maxWidth: 520,
               minHeight: 226, maxHeight: 700)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                Button("打开备忘录 App") { vm.openNotesApp() }
                Button(vm.launchAtLogin ? "开机自启：已开启 ✓" : "开机自启：未开启") {
                    vm.toggleLaunchAtLogin()
                }
                Button("清除草稿") { vm.clearAll() }
                Divider()
                Button("退出 azure桌面小板") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer()
            Text("azure桌面小板")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Color.clear.frame(width: 18, height: 18)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            statusLine
            Button {
                vm.save()
            } label: {
                Text(vm.isSaving ? "保存中…" : "保存到备忘录")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor).opacity(vm.isSaving ? 0.4 : 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(vm.isSaving)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.45))
    }

    private var statusLine: some View {
        let label: (String, Color) = {
            switch vm.saveState {
            case .saving:
                return ("正在保存到备忘录…", .secondary)
            case .success:
                return ("已保存 ✓", .green)
            case .failure(let message):
                return ("保存失败：\(message)（草稿已保留）", .red)
            case .idle:
                if let hint = vm.ocrHint {
                    return (hint, .secondary)
                }
                if vm.suggestionVisible {
                    return ("↩ 回车固定答案", .secondary)
                }
                if vm.draftPending {
                    return ("草稿自动保存中…", .secondary)
                }
                if let date = vm.draftSavedAt {
                    return ("草稿已存 \(Self.timeText(date))", .secondary)
                }
                return ("输入即自动存草稿", .secondary)
            }
        }()
        return Text(label.0)
            .font(.system(size: 10))
            .foregroundStyle(label.1)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// 输入区背景：跟随系统外观，白天极浅灰、夜间深灰
extension Color {
    static let editorBackground = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        if isDark {
            return NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)    // #29292B 深灰
        } else {
            return NSColor(srgbRed: 0.955, green: 0.955, blue: 0.96, alpha: 1)  // #F4F4F5 极浅灰
        }
    })
}
