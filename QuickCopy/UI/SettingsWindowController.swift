import AppKit
import SwiftUI

/// 设置的独立窗口。菜单栏 App 没有主窗口，所以手动托管一个 NSWindow。
final class SettingsWindowController: NSWindowController {
    private let actionInteraction: ActionRowInteraction

    init(config: ConfigManager,
         accessibility: AccessibilityService,
         actionManager: ActionManager,
         coordinator: AppCoordinator) {
        let actionInteraction = ActionRowInteraction()
        self.actionInteraction = actionInteraction

        // 未授权时直接落在“隐私与权限”，避免第一次打开设置却找不到授权入口。
        let navigation = SettingsNavigation(
            selectedPage: accessibility.isTrusted ? .appearance : .privacy
        )

        let rootView = SettingsView(
            config: config,
            accessibility: accessibility,
            actionManager: actionManager,
            coordinator: coordinator,
            navigation: navigation,
            actionInteraction: actionInteraction
        )
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)

        window.title = "QuickCopy 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.setContentSize(NSSize(width: 900, height: 660))
        window.minSize = NSSize(width: 800, height: 560)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}