import AppKit

/// 内置动作：把选中的文字写进系统剪贴板。
///
/// 注意：QuickCopy 不拦截、不重写系统 ⌘C。只有用户点击胶囊按钮时，
/// 才会调用这里的 perform；平时 ⌘C 完全由系统和原 App 处理。
final class CopyAction: QuickAction {
    let id = "copy"
    let title = "复制"
    let systemImageName = "doc.on.doc"
    let isEnabled = true

    func perform(on context: SelectionContext,
                 completion: @escaping (QuickActionResult) -> Void) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(context.text, forType: .string) {
            completion(.success)
        } else {
            completion(.failure("无法写入系统剪贴板"))
        }
    }
}