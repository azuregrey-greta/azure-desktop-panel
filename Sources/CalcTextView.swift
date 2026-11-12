import AppKit
import Combine
import SwiftUI

/// 带四则运算「幽灵答案」的输入区：
/// 行尾输入 "=" 时右侧立即显示灰色答案（不写入正文/草稿），
/// 回车把答案固定成正文并换行；光标移走或继续编辑则答案消失。
struct CalcTextView: NSViewRepresentable {
    @ObservedObject var vm: PanelViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(vm: vm)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.font = NSFont.systemFont(ofSize: 12)
        tv.textColor = .labelColor
        tv.typingAttributes = Coordinator.baseAttributes
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]

        tv.string = vm.text
        let initial = vm.text as NSString
        tv.textStorage?.setAttributes(
            Coordinator.baseAttributes,
            range: NSRange(location: 0, length: initial.length))
        tv.selectedRange = NSRange(location: initial.length, length: 0)

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        if let container = tv.textContainer {
            container.widthTracksTextView = true
            container.containerSize = NSSize(
                width: scroll.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude)
            container.lineFragmentPadding = 2
        }

        context.coordinator.attach(tv)
        context.coordinator.refreshGhost(notifyText: false)
        context.coordinator.observeVM()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator: NSObject, NSTextViewDelegate {
        struct Ghost {
            let lineStart: Int
            let answer: String
        }

        static let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]
        static let ghostAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        private let vm: PanelViewModel
        private weak var textView: NSTextView?
        private var ghost: Ghost?
        private var cancellable: AnyCancellable?

        init(vm: PanelViewModel) {
            self.vm = vm
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(_ tv: NSTextView) {
            textView = tv
        }

        /// 跟随 ViewModel 的外部文本变化（保存成功清空 / 清除草稿 / 草稿恢复）
        func observeVM() {
            guard let tv = textView else { return }
            cancellable = vm.$text.sink { [weak self] newText in
                guard let self, let tv = self.textView else { return }
                guard tv.string != newText else { return }
                self.ghost = nil
                tv.textStorage?.beginEditing()
                tv.textStorage?.setAttributedString(
                    NSAttributedString(string: newText, attributes: Self.baseAttributes))
                tv.textStorage?.endEditing()
                let ns = newText as NSString
                tv.selectedRange = NSRange(location: ns.length, length: 0)
                self.vm.setSuggestionVisible(false)
            }
            NotificationCenter.default.addObserver(
                self, selector: #selector(selectionChanged),
                name: NSTextView.didChangeSelectionNotification, object: tv)
        }

        @objc private func selectionChanged() {
            refreshGhost(notifyText: false)
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            refreshGhost(notifyText: true)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return commitGhostAndNewline()
            }
            return false
        }

        // MARK: - 幽灵答案核心

        func refreshGhost(notifyText: Bool) {
            guard let tv = textView else { return }
            stripGhost()
            if notifyText {
                vm.text = tv.string // 干净文本 → didSet 防抖落盘
            }
            if let (lineStart, answer) = ghostCandidateAtCaret() {
                let attr = NSAttributedString(string: answer, attributes: Self.ghostAttributes)
                tv.textStorage?.replaceCharacters(
                    in: NSRange(location: tv.selectedRange.location, length: 0),
                    with: attr)
                ghost = Ghost(lineStart: lineStart, answer: answer)
            }
            vm.setSuggestionVisible(ghost != nil)
        }

        private func ghostCandidateAtCaret() -> (lineStart: Int, answer: String)? {
            guard let tv = textView else { return nil }
            guard tv.markedRange().length == 0 else { return nil } // IME 组字期间不打扰
            let sel = tv.selectedRange
            guard sel.length == 0 else { return nil }
            let ns = tv.string as NSString
            let length = ns.length
            let caret = min(sel.location, length)

            let before = ns.substring(to: caret)
            let newline = (before as NSString).range(of: "\n", options: .backwards)
            let lineStart = newline.location == NSNotFound ? 0 : newline.location + 1

            // 光标必须处于行尾（同一行光标后面没有别的字符）
            if caret < length {
                let next = ns.character(at: caret)
                if next != unichar(0x0A) { return nil }
            }

            let candidate = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
            let trimmed = ExpressionEvaluator.mapSymbols(candidate)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasSuffix("=") else { return nil }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 2 else { return nil }
            let expr = parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
            guard !expr.isEmpty,
                  let value = ExpressionEvaluator.evaluate(expr),
                  let answer = ExpressionEvaluator.format(value) else { return nil }
            return (lineStart, answer)
        }

        private func stripGhost() {
            guard ghost != nil else { return }
            if let range = locateGhostRange() {
                textView?.textStorage?.replaceCharacters(
                    in: range,
                    with: NSAttributedString(string: "", attributes: Self.baseAttributes))
            }
            ghost = nil
        }

        /// 回车：把灰色答案刷成正文颜色，然后换行
        private func commitGhostAndNewline() -> Bool {
            guard let tv = textView, ghost != nil, let range = locateGhostRange() else {
                ghost = nil
                return false
            }
            let storage = tv.textStorage
            storage?.beginEditing()
            storage?.setAttributes(Self.baseAttributes, range: range)
            storage?.replaceCharacters(
                in: NSRange(location: range.location + range.length, length: 0),
                with: NSAttributedString(string: "\n", attributes: Self.baseAttributes))
            storage?.endEditing()
            ghost = nil
            tv.selectedRange = NSRange(location: range.location + range.length + 1, length: 0)
            tv.scrollRangeToVisible(tv.selectedRange)
            vm.setSuggestionVisible(false)
            vm.text = tv.string
            return true
        }

        /// 在幽灵所在行里重新定位它的范围（行内容可能被用户编辑过，位置会漂移）
        private func locateGhostRange() -> NSRange? {
            guard let tv = textView, let ghost else { return nil }
            let ns = tv.string as NSString
            let length = ns.length
            let start = min(ghost.lineStart, length)
            var lineEnd = start
            while lineEnd < length {
                if ns.character(at: lineEnd) == unichar(0x0A) { break }
                lineEnd += 1
            }
            let lineRange = NSRange(location: start, length: lineEnd - start)
            let answerLength = (ghost.answer as NSString).length

            let eq = ns.range(of: "=", options: [], range: lineRange)
            if eq.location != NSNotFound {
                let answerStart = eq.location + 1
                if length - answerStart >= answerLength,
                   ns.substring(with: NSRange(location: answerStart, length: answerLength)) == ghost.answer {
                    return NSRange(location: answerStart, length: answerLength)
                }
            }
            let fallback = ns.range(of: ghost.answer, options: [], range: lineRange)
            if fallback.location != NSNotFound {
                return fallback
            }
            return nil
        }
    }
}
