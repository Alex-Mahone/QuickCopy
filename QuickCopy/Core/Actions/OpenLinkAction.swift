import AppKit

/// 内置动作：用系统默认浏览器打开选中的网页链接。
///
/// 只在整段选区就是一个 `http(s)` 链接时出现；QuickCopy 不抓取网页、
/// 不联网，只把识别到的 URL 交给 `NSWorkspace`，由系统浏览器打开。
final class OpenLinkAction: QuickAction {
    let id = "openLink"
    let title = "打开链接"
    let systemImageName = "link"
    /// 和“搜索”同属额外入口，在胶囊里与剪切/复制等编辑动作分隔。
    let visualGroup = 1
    let isEnabled = true

    func isAvailable(for context: SelectionContext) -> Bool {
        WebLinkDetector.url(in: context.text) != nil
    }

    func perform(on context: SelectionContext,
                 completion: @escaping (QuickActionResult) -> Void) {
        guard let url = WebLinkDetector.url(in: context.text) else {
            completion(.failure("选中的文字不是网页链接"))
            return
        }

        if NSWorkspace.shared.open(url) {
            completion(.success)
        } else {
            completion(.failure("无法打开链接"))
        }
    }
}