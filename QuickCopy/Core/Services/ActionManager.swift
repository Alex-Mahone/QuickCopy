import Combine
import Foundation

/// 统一注册、筛选、执行所有胶囊动作。
///
/// 动作的注册顺序决定默认展示顺序；配置中的 `enabledActionIDs`
/// 决定展示哪些动作以及最终顺序。ActionManager 不认识 SwiftUI，
/// 也不认识悬浮窗，只负责“有哪些动作”和“执行哪一个”。
final class ActionManager: ObservableObject {
    @Published private(set) var actions: [QuickAction] = []

    private var registry: [String: QuickAction] = [:]

    /// 注册一个动作。重复的 id 会被忽略，避免运行时重复注入。
    func register(_ action: QuickAction) {
        guard registry[action.id] == nil else { return }
        registry[action.id] = action
        actions.append(action)
    }

    /// 按配置里的顺序返回当前可用的动作。
    func enabledActions(for enabledIDs: [String]) -> [QuickAction] {
        var seen = Set<String>()
        return enabledIDs.compactMap { id in
            guard let action = registry[id], action.isEnabled, !seen.contains(id) else {
                return nil
            }
            seen.insert(id)
            return action
        }
    }

    /// 执行动作，并保证 completion 回到主线程（异步动作可能在其他队列回调）。
    func perform(_ action: QuickAction,
                 on context: SelectionContext,
                 completion: @escaping (QuickActionResult) -> Void) {
        guard registry[action.id] === action else {
            completion(.failure("动作未注册：\(action.id)"))
            return
        }
        guard action.isEnabled else {
            completion(.failure("动作当前不可用：\(action.title)"))
            return
        }
        guard action.isAvailable(for: context) else {
            completion(.failure("动作不适用于当前选区：\(action.title)"))
            return
        }

        action.perform(on: context) { result in
            if Thread.isMainThread {
                completion(result)
            } else {
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }
}