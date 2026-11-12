import Foundation

/// 通过 osascript（AppleScript）调用「备忘录」保存内容：
/// 每次保存都把「时间戳 + 正文」追加到同一条「azure桌面小板」备忘录末尾，没有就自动创建。
final class NotesSaver {
    struct ScriptError: Error {
        let exitCode: Int32
        let message: String
        let timedOut: Bool
    }

    static let noteTitle = "azure桌面小板"
    private let queue = DispatchQueue(label: "com.azure.smallpanel.notessaver", qos: .userInitiated)
    private let timeout: TimeInterval = 45

    /// completion 参数为 nil 表示成功；否则是给用户看的错误信息。
    func append(_ content: String, completion: @escaping (String?) -> Void) {
        queue.async {
            do {
                try self.appendSync(content)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                let message = Self.friendlyMessage(for: error)
                DispatchQueue.main.async { completion(message) }
            }
        }
    }

    private func appendSync(_ content: String) throws {
        let html = Self.buildHTML(for: content)
        // 正文通过临时文件传给 AppleScript，
        // 彻底避开换行、引号、特殊字符的转义问题（比 URL 编码更稳）
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("azure-panel-body-\(UUID().uuidString).html")
        try Data(html.utf8).write(to: bodyURL)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        let script = """
        set bodyHTML to read POSIX file "\(bodyURL.path)" as «class utf8»
        set noteTitle to "\(Self.noteTitle)"
        tell application "Notes"
            set theNote to missing value
            try
                set theNote to first note of default account whose name is noteTitle
            end try
            if theNote is missing value then
                set theNote to make new note with properties {name:noteTitle}
            end if
            set body of theNote to (body of theNote as text) & bodyHTML
            return id of theNote
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()

        final class FlagBox { var value = false }
        let terminatedByWatchdog = FlagBox()
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                terminatedByWatchdog.value = true
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()

        if process.terminationStatus == 0 { return }

        let stderrText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        throw ScriptError(
            exitCode: process.terminationStatus,
            message: stderrText,
            timedOut: terminatedByWatchdog.value
        )
    }

    // MARK: - HTML 组装（备忘录正文是 HTML）

    private static func buildHTML(for content: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stamp = escape(formatter.string(from: Date()))

        var html = "<div><br></div>"
        html += "<div><span style=\"color:#98989d;font-size:12px\">—— \(stamp) · azure桌面小板</span></div>"
        for line in content.components(separatedBy: "\n") {
            let escaped = escape(line)
            html += escaped.isEmpty ? "<div><br></div>" : "<div>\(escaped)</div>"
        }
        html += "<div><br></div>"
        return html
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - 错误信息（给用户看）

    private static func friendlyMessage(for error: Error) -> String {
        guard let scriptError = error as? ScriptError else {
            return error.localizedDescription
        }
        if scriptError.timedOut {
            return "备忘录无响应（超时）"
        }
        let lower = scriptError.message.lowercased()
        if scriptError.message.contains("-1743")
            || lower.contains("not allowed")
            || lower.contains("not authorized") {
            return "未授权访问备忘录（系统设置→隐私与安全性→自动化）"
        }
        let firstLine = scriptError.message
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "未知错误"
        return "osascript \(scriptError.exitCode)：\(String(firstLine.prefix(80)))"
    }
}
