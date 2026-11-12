import Foundation

/// 四则运算求值：只认数字、加减乘除、括号和小数点，任何问题都返回 nil（不显示答案）。
/// 不用 NSExpression，避免对打字中途的畸形输入抛 ObjC 异常导致崩溃。
enum ExpressionEvaluator {
    static func mapSymbols(_ text: String) -> String {
        var result = text
        for (symbol, replacement) in ["×": "*", "÷": "/", "＋": "+", "－": "-", "＝": "="] {
            result = result.replacingOccurrences(of: symbol, with: replacement)
        }
        return result
    }

    static func evaluate(_ raw: String) -> Double? {
        let compact = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty, compact.count <= 200 else { return nil }
        guard compact.contains(where: { $0.isNumber }) else { return nil }
        let allowed = Set("0123456789.+-*/()")
        guard compact.allSatisfy({ allowed.contains($0) }) else { return nil }

        var parser = Parser(Array(compact))
        guard let value = parser.parseExpression(), parser.isAtEnd(), value.isFinite else { return nil }
        return value
    }

    /// 结果格式化：整数去掉小数点，非整数最多保留 10 位并去掉多余的 0（0.1+0.2 → 0.3）
    static func format(_ value: Double) -> String? {
        guard value.isFinite else { return nil }
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int64(value.rounded()))
        }
        if abs(value) >= 1e15 {
            return String(format: "%.6g", value)
        }
        var text = String(format: "%.10f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    private struct Parser {
        private let chars: [Character]
        private var index = 0

        init(_ chars: [Character]) {
            self.chars = chars
        }

        func isAtEnd() -> Bool { index >= chars.count }
        private var current: Character? { index < chars.count ? chars[index] : nil }

        // expression := term (('+' | '-') term)*
        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = current, op == "+" || op == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        // term := factor (('*' | '/') factor)*
        mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let op = current, op == "*" || op == "/" {
                index += 1
                guard let rhs = parseFactor() else { return nil }
                if op == "/" {
                    guard rhs != 0 else { return nil }
                    value = value / rhs
                } else {
                    value = value * rhs
                }
            }
            return value
        }

        // factor := ('-' | '+')* primary
        mutating func parseFactor() -> Double? {
            if let op = current, op == "-" {
                index += 1
                guard let value = parseFactor() else { return nil }
                return -value
            }
            if let op = current, op == "+" {
                index += 1
                return parseFactor()
            }
            return parsePrimary()
        }

        // primary := number | '(' expression ')'
        mutating func parsePrimary() -> Double? {
            if let char = current, char == "(" {
                index += 1
                guard let value = parseExpression() else { return nil }
                guard let close = current, close == ")" else { return nil }
                index += 1
                return value
            }
            return parseNumber()
        }

        mutating func parseNumber() -> Double? {
            var text = ""
            while let char = current, char.isNumber || char == "." {
                text.append(char)
                index += 1
            }
            guard !text.isEmpty,
                  text.filter({ $0 == "." }).count <= 1,
                  let value = Double(text) else { return nil }
            return value
        }
    }
}
