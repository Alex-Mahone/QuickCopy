import Foundation

/// 动作执行结果。
///
/// 当前复制动作是同步完成的；保留 completion 形式是为了后续接入翻译、
/// 上传到剪贴板历史等异步动作时，弹窗层不需要改动。
enum QuickActionResult {
    case success
    case failure(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}