import AppKit
import Vision

/// 用系统 Vision 框架识别图片里的文字（中英文），不需要额外授权。
enum ImageOCR {
    static let languages = ["zh-Hans", "zh-Hant", "en-US"]

    /// 后台识别，completion 在主线程回调；识别不到返回空字符串。
    static func recognize(_ image: NSImage, completion: @escaping (String) -> Void) {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            completion("")
            return
        }
        recognize(cgImage: cgImage, completion: completion)
    }

    static func recognize(cgImage: CGImage, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            var text = ""
            do {
                try handler.perform([request])
                let lines = (request.results ?? []).compactMap { observation -> String? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return candidate.string
                }
                text = lines.joined(separator: "\n")
            } catch {
                text = ""
            }
            let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { completion(result) }
        }
    }
}
