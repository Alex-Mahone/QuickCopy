import AppKit

/// 菜单栏模块。只负责状态栏图标与菜单，不直接持有业务服务。
///
/// 所有行为通过 `Callbacks` 注入，方便以后替换实现或单独测试。
final class MenuBarManager: NSObject, NSMenuDelegate {
    struct Callbacks {
        var isMonitoringEnabled: () -> Bool
        var setMonitoringEnabled: (Bool) -> Void
        var isAccessibilityTrusted: () -> Bool
        var refreshPermission: () -> Void
        var openSettings: () -> Void
        var openAccessibilitySettings: () -> Void
        var quit: () -> Void
    }

    private let callbacks: Callbacks
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var monitoringItem: NSMenuItem!
    private var permissionItem: NSMenuItem!

    init(callbacks: Callbacks) {
        self.callbacks = callbacks
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        if let button = statusItem.button {
            let symbol = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: "QuickCopy"
            )
            symbol?.isTemplate = true
            button.image = symbol
            button.toolTip = "QuickCopy — 划词复制"
        }

        buildMenu()
        statusItem.menu = menu
        refreshAppearance()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// 设置页或代码改变监听状态后，同步图标外观。
    func refreshAppearance() {
        let enabled = callbacks.isMonitoringEnabled()
        statusItem.button?.appearsDisabled = !enabled
        monitoringItem?.state = enabled ? .on : .off
        updatePermissionItem()
    }

    private func buildMenu() {
        menu.delegate = self

        monitoringItem = NSMenuItem(
            title: "启用划词",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        monitoringItem.target = self
        menu.addItem(monitoringItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        permissionItem = NSMenuItem(
            title: "辅助功能权限…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 QuickCopy",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func updatePermissionItem() {
        let trusted = callbacks.isAccessibilityTrusted()
        permissionItem.title = trusted ? "辅助功能权限（已授权）…" : "辅助功能权限（未授权，必需）…"
        permissionItem.image = NSImage(
            systemSymbolName: trusted ? "checkmark.seal" : "exclamationmark.triangle",
            accessibilityDescription: nil
        )
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // 用户可能刚从系统设置授权回来；打开菜单时顺便检查一次。
        callbacks.refreshPermission()
        refreshAppearance()
    }

    // MARK: - Actions

    @objc private func toggleMonitoring() {
        let next = !callbacks.isMonitoringEnabled()
        callbacks.setMonitoringEnabled(next)
        refreshAppearance()
    }

    @objc private func openSettings() {
        callbacks.openSettings()
    }

    @objc private func openAccessibilitySettings() {
        callbacks.openAccessibilitySettings()
    }

    @objc private func quit() {
        callbacks.quit()
    }
}