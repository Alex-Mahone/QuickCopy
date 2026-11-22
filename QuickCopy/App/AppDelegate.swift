import AppKit

/// 应用生命周期：装配依赖、安装菜单栏、托管设置窗口。
///
/// 所有业务都在 AppCoordinator 里，AppDelegate 只做“接线”和 AppKit 入口。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator!
    private var menuBarManager: MenuBarManager!
    private var settingsWindowController: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        coordinator = AppCoordinator()

        settingsWindowController = SettingsWindowController(
            config: coordinator.config,
            accessibility: coordinator.accessibility,
            actionManager: coordinator.actionManager,
            coordinator: coordinator
        )

        menuBarManager = MenuBarManager(callbacks: MenuBarManager.Callbacks(
            isMonitoringEnabled: { [weak coordinator] in
                coordinator?.isMonitoringEnabled ?? false
            },
            setMonitoringEnabled: { [weak coordinator] enabled in
                coordinator?.setMonitoringEnabled(enabled)
            },
            isAccessibilityTrusted: { [weak coordinator] in
                coordinator?.accessibility.isTrusted ?? false
            },
            refreshPermission: { [weak coordinator] in
                coordinator?.refreshAccessibilityPermission()
            },
            openSettings: { [weak self] in
                self?.settingsWindowController.show()
            },
            openAccessibilitySettings: { [weak coordinator] in
                coordinator?.openAccessibilitySettings()
            },
            quit: {
                NSApp.terminate(nil)
            }
        ))

        coordinator.onMonitoringStateChanged = { [weak self] in
            self?.menuBarManager.refreshAppearance()
        }

        installMainMenu()
        coordinator.start()
        coordinator.presentPermissionGuideIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 QuickCopy",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        let closeItem = NSMenuItem(
            title: "关闭",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(closeItem)
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu() {
        settingsWindowController.show()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }
}