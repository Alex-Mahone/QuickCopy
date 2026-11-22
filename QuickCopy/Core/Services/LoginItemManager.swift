import Foundation
import ServiceManagement

/// 开机自启封装（macOS 13+ SMAppService）。
///
/// 说明：
/// - 使用公开 API，不使用已废弃的 SMLoginItemSetEnabled。
/// - 未沙盒的本地 App 也可使用 `SMAppService.mainApp`。
/// - 开发构建如果不在 /Applications 下，注册可能失败；这是系统限制，
///   设置页会把错误原文展示出来，不会假装成功。
struct LoginItemManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled else { return }
            try service.unregister()
        }
    }
}