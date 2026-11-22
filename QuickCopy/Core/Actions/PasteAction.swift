import AppKit

/// 内置动作：把系统剪贴板粘贴到当前选区。
///
/// 同样只发送标准 ⌘V，由原 App 自己插入内容；QuickCopy 不读写、不改写
/// 剪贴板，图片、文件、富文本等格式都保持原 App 的原生粘贴行为。
final class PasteAction: QuickAction {
    let id = "paste"
    let title = "粘贴"
    let systemImageName = "doc.on.clipboard"
    let isEnabled = true
    let requiresEditableText = true

    func perform(on context: SelectionContext,
                 completion: @escaping (QuickActionResult) -> Void) {
        let pasteboard = NSPasteboard.general
        guard let types = pasteboard.types, !types.isEmpty else {
            completion(.failure("剪贴板是空的"))
            return
        }

        guard let pid = context.sourceProcessIdentifier else {
            completion(.failure("找不到选区所属的 App"))
            return
        }

        KeyboardEventSender.send(.paste, to: pid) { sent in
            guard sent else {
                completion(.failure("无法向来源 App 发送粘贴指令"))
                return
            }

            // 无法从外部可靠判断目标 App 是否接受粘贴，事件成功投递即视为完成。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                completion(.success)
            }
        }
    }
}