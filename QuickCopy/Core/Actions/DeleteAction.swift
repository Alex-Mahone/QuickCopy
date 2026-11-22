import AppKit

/// 内置动作：删除当前选中的文字。
///
/// 只向来源 App 发送标准的 Delete（退格）键，由原 App 自己删除选区；
/// 不读取、不写入剪贴板，因此不会覆盖用户已复制的内容。
final class DeleteAction: QuickAction {
    let id = "delete"
    let title = "删除"
    let systemImageName = "delete.left"
    let isEnabled = true
    let requiresEditableText = true

    func perform(on context: SelectionContext,
                 completion: @escaping (QuickActionResult) -> Void) {
        guard let pid = context.sourceProcessIdentifier else {
            completion(.failure("找不到选区所属的 App"))
            return
        }

        KeyboardEventSender.send(.delete, to: pid) { sent in
            guard sent else {
                completion(.failure("无法向来源 App 发送删除指令"))
                return
            }

            // 无法从外部可靠确认目标 App 是否接受删除，事件成功投递即视为完成。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                completion(.success)
            }
        }
    }
}