import AppKit

/// 内置动作：剪切选中的文字。
///
/// 做法和用户在键盘上按 ⌘X 完全一致：把标准快捷键定向发给选区所属 App，
/// 由原 App 完成“写入剪贴板 + 删除选区”，保持字体、富文本等原生行为。
/// QuickCopy 不直接修改文本内容，也不拦截任何系统快捷键。
final class CutAction: QuickAction {
    let id = "cut"
    let title = "剪切"
    let systemImageName = "scissors"
    let isEnabled = true
    let requiresEditableText = true

    func perform(on context: SelectionContext,
                 completion: @escaping (QuickActionResult) -> Void) {
        guard let pid = context.sourceProcessIdentifier else {
            completion(.failure("找不到选区所属的 App"))
            return
        }

        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount

        KeyboardEventSender.send(.cut, to: pid) { sent in
            guard sent else {
                completion(.failure("无法向来源 App 发送剪切指令"))
                return
            }

            // 等原 App 处理完 ⌘X，再确认它确实改写了剪贴板。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let changed = pasteboard.changeCount != before
                let matched = pasteboard.string(forType: .string) == context.text
                if changed || matched {
                    completion(.success)
                } else {
                    completion(.failure("来源 App 没有响应剪切"))
                }
            }
        }
    }
}