import AppKit

/// 内置动作：用系统搜索打开选中的文字。
///
/// 调用 macOS Services 中 Safari 提供的「Search With %WebSearchProvider@」
/// 服务，行为与文本右键菜单里的“用某搜索引擎搜索”一致：使用系统当前
/// 的默认搜索引擎，在 Safari 中打开结果页。QuickCopy 不内置搜索框，
/// 也不采集查询内容。
final class SearchAction: QuickAction {
    let id = "search"
    let title = "搜索"
    let systemImageName = "magnifyingglass"
    /// 和剪切/复制/粘贴/删除之间画一条分隔线，作为额外入口单独分组。
    let visualGroup = 1
    /// 额外入口只显示图标，悬停时仍会显示“搜索”。
    let showsTitle = false
    let isEnabled = true

    func perform(on context: SelectionContext,
                 completion: @escaping (QuickActionResult) -> Void) {
        let query = context.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            completion(.failure("没有可搜索的文字"))
            return
        }

        // 用独立剪贴板承载查询词，避免覆盖用户当前复制的内容。
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.jeff.quickcopy.search"))
        pasteboard.clearContents()
        guard pasteboard.setString(query, forType: .string) else {
            completion(.failure("无法准备搜索文字"))
            return
        }

        if NSPerformService("Search With %WebSearchProvider@", pasteboard) {
            completion(.success)
            return
        }

        // 系统服务不可用时退回默认浏览器；当前系统默认搜索是百度。
        if let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://www.baidu.com/s?wd=\(encoded)") {
            NSWorkspace.shared.open(url)
            completion(.success)
        } else {
            completion(.failure("系统搜索服务不可用"))
        }
    }
}