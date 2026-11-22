import AppKit

/// 纯 AppKit 生命周期。菜单栏 App 没有主窗口，也不需要 SwiftUI App/Scene：
/// SwiftUI 负责所有可见内容（胶囊、设置页），窗口与状态栏由 AppKit 精确托管。
@main
enum QuickCopyApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}