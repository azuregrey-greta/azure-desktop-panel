import AppKit

/// 只接受纯文本的输入框：
/// - ⌘V / 拖拽 → 丢掉字体、颜色、附件，只保留文字
/// - 剪贴板里只有图片时 → 走系统 OCR 识别文字后插入
/// - 图片里识别不出字 → 什么也不插，通过回调提示用户
final class PlainTextTextView: NSTextView {
    /// 识别中/失败等状态提示（由 Coordinator 接到状态栏）
    var onTransientMessage: ((String?) -> Void)?

    override func paste(_ sender: Any?) {
        handleTransfer(NSPasteboard.general)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        handleTransfer(NSPasteboard.general)
    }

    /// 拖拽时允许的类型：纯文本 + 图片（图片会走 OCR）
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string, .png, .tiff]
    }

    /// 拖拽落入 / 粘贴统一入口
    override func readSelection(from pasteboard: NSPasteboard) -> Bool {
        handleTransfer(pasteboard)
    }

    @discardableResult
    private func handleTransfer(_ pasteboard: NSPasteboard) -> Bool {
        // 1. 有文字就直接用文字（最关键的一条：富文本只取纯文本部分）
        if let raw = pasteboard.string(forType: .string) {
            let plain = Self.normalize(raw)
            if !plain.isEmpty {
                insertText(plain, replacementRange: selectedRange())
                return true
            }
        }

        // 2. 没文字就看有没有图片，走 OCR
        guard let image = Self.image(from: pasteboard) else { return false }
        onTransientMessage?("正在识别图片文字…")
        ImageOCR.recognize(image) { [weak self] text in
            guard let self else { return }
            if text.isEmpty {
                self.onTransientMessage?("图片里没识别到文字")
            } else {
                self.onTransientMessage?("已从图片识别 \(text.count) 个字符")
                self.insertText(text, replacementRange: self.selectedRange())
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.onTransientMessage?(nil)
            }
        }
        return true
    }

    private static func image(from pasteboard: NSPasteboard) -> NSImage? {
        if let image = NSImage(pasteboard: pasteboard) { return image }
        return nil
    }

    /// 清洗：统一换行、去掉不换行空格和零宽字符
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{200B}", with: "")
    }
}
