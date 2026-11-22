import Foundation

/// 从选区文字里识别网页链接。
///
/// 只接受整段选区就是一个链接（允许外层标点，如括号、句号），
/// 避免在一段普通文字里悄悄打开某个链接。支持 `http(s)://`、`www.`
/// 和常见裸域名；`mailto:`、`file://` 等其它 scheme 会被拒绝。
enum WebLinkDetector {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func url(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4096 else { return nil }

        // 链接本身不含空白；先做便宜过滤，普通划词不必启动数据检测器。
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        let lowercased = trimmed.lowercased()
        guard lowercased.hasPrefix("http://")
                || lowercased.hasPrefix("https://")
                || trimmed.contains(".") else {
            return nil
        }

        guard let detector else { return nil }
        let fullRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let matches = detector.matches(in: trimmed, options: [], range: fullRange)
        guard matches.count == 1,
              let match = matches.first,
              let matchRange = Range(match.range, in: trimmed),
              let url = match.url else {
            return nil
        }

        // 链接前后只允许标点/引号/括号，像“看这个 https://…”或
        // “链接：https://…”这种带说明文字的选择不弹打开链接。
        let leading = trimmed[..<matchRange.lowerBound]
        let trailing = trimmed[matchRange.upperBound...]
        guard isOnlyPunctuation(leading), isOnlyPunctuation(trailing) else {
            return nil
        }

        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        return url
    }

    private static func isOnlyPunctuation(_ substring: Substring) -> Bool {
        substring.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0)
                || CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }
}