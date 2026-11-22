import AppKit
import Combine
import Foundation

/// 应用协调器：唯一同时认识各层的对象。
///
/// 数据流：
/// AccessibilityService → AppCoordinator → CapsuleController → FloatingCapsuleView
/// 用户点按钮 → CapsuleController → AppCoordinator → ActionManager → CopyAction
///
/// 各层之间不互相引用，新增动作/设置项只需在这里接线。
final class AppCoordinator: ObservableObject {
    let config: ConfigManager
    let accessibility: AccessibilityService
    let actionManager: ActionManager
    let capsule: CapsuleController

    @Published private(set) var isMonitoringEnabled = true
    @Published private(set) var launchAtLoginError: String?

    /// 菜单栏图标状态刷新。
    var onMonitoringStateChanged: (() -> Void)?

    private let loginItemManager = LoginItemManager()
    private var cancellables = Set<AnyCancellable>()
    private var activationObserver: NSObjectProtocol?
    private var isRevertingLaunchAtLogin = false

    init(config: ConfigManager = ConfigManager(),
         accessibility: AccessibilityService = AccessibilityService(),
         actionManager: ActionManager = ActionManager(),
         capsule: CapsuleController = CapsuleController()) {
        self.config = config
        self.accessibility = accessibility
        self.actionManager = actionManager
        self.capsule = capsule

        registerActions()
        wireLayers()
        observeConfiguration()
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    // MARK: - Lifecycle

    func start() {
        applyLiveConfiguration()
        syncLaunchAtLoginAtStartup()
        capsule.prewarm(
            actions: actionManager.enabledActions(for: config.enabledActionIDs),
            configuration: config.capsuleConfiguration
        )
        accessibility.start()
    }

    func stop() {
        accessibility.stop()
        capsule.hide(reason: .manual)
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    /// 首次启动时触发一次系统辅助功能授权提示。
    /// 之后由设置页 / 菜单栏提供入口，不反复弹窗。
    func presentPermissionGuideIfNeeded() {
        guard !accessibility.isTrusted else { return }

        let key = "quickcopy.didPromptAccessibility"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        accessibility.requestPermissionPrompt()
    }

    // MARK: - Wiring

    private func registerActions() {
        // 注册顺序就是首次展示顺序：剪切 → 复制 → 粘贴 → 删除 | 打开链接 搜索。
        // 之后用户可在设置页里增删或调整启用顺序。
        actionManager.register(CutAction())
        actionManager.register(CopyAction())
        actionManager.register(PasteAction())
        actionManager.register(DeleteAction())
        actionManager.register(OpenLinkAction())
        actionManager.register(SearchAction())
    }

    private func wireLayers() {
        accessibility.onSelection = { [weak self] context in
            self?.handleSelection(context)
        }
        accessibility.onSelectionCleared = { [weak self] in
            self?.capsule.selectionDidClear()
        }
        capsule.onPerform = { [weak self] action, context in
            self?.perform(action: action, context: context)
        }

        // 打开设置窗口、从系统设置返回时都可能改变授权状态。
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAccessibilityPermission()
        }
    }

    private func observeConfiguration() {
        // 键盘选字配置变化时，立即同步给监听层。
        config.$showOnKeyboardSelection
            .removeDuplicates()
            .sink { [weak self] value in
                self?.accessibility.options.showOnKeyboardSelection = value
            }
            .store(in: &cancellables)

        // 外观类配置变化时，更新已显示的胶囊。
        config.objectWillChange
            .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.capsule.updateConfiguration(self.config.capsuleConfiguration)
            }
            .store(in: &cancellables)

        // 开机自启是副作用操作，不在 ConfigManager 里直接做。
        config.$launchAtLogin
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.applyLaunchAtLogin(enabled)
            }
            .store(in: &cancellables)

        // 排除列表变化后收起当前胶囊，避免刚加入排除的应用/网站还残留按钮。
        config.$excludedAppBundleIDs
            .dropFirst()
            .sink { [weak self] _ in
                self?.capsule.hide(reason: .manual)
            }
            .store(in: &cancellables)

        config.$excludedSiteHosts
            .dropFirst()
            .sink { [weak self] _ in
                self?.capsule.hide(reason: .manual)
            }
            .store(in: &cancellables)
    }

    private func applyLiveConfiguration() {
        accessibility.options.showOnKeyboardSelection = config.showOnKeyboardSelection
        capsule.updateConfiguration(config.capsuleConfiguration)
    }

    // MARK: - Selection flow

    private func handleSelection(_ context: SelectionContext) {
        guard isMonitoringEnabled else { return }

        // 应用排除列表：在这些 App 中划词不弹胶囊。
        if config.isAppExcluded(context.sourceBundleIdentifier) {
            capsule.hide(reason: .manual)
            return
        }

        // 网站排除列表：在指定域名的网页里划词不弹胶囊。
        if config.isSiteExcluded(context.pageURL) {
            capsule.hide(reason: .manual)
            return
        }

        let actions = actionManager.enabledActions(for: config.enabledActionIDs)
            .filter { !$0.requiresEditableText || context.isEditable }
            .filter { $0.isAvailable(for: context) }
        guard !actions.isEmpty else {
            capsule.hide(reason: .manual)
            return
        }

        capsule.show(
            context: context,
            actions: actions,
            configuration: config.capsuleConfiguration
        )
    }

    private func perform(action: QuickAction, context: SelectionContext) {
        actionManager.perform(action, on: context) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.capsule.showFeedback(actionID: action.id, success: true)
            case .failure(let message):
                NSLog("QuickCopy action \(action.id) failed: \(message)")
                self.capsule.showFeedback(actionID: action.id, success: false)
            }
        }
    }

    // MARK: - Monitoring toggle

    func setMonitoringEnabled(_ enabled: Bool) {
        guard enabled != isMonitoringEnabled else { return }
        isMonitoringEnabled = enabled

        if enabled {
            accessibility.start()
        } else {
            accessibility.stop()
            capsule.hide(reason: .manual)
        }

        onMonitoringStateChanged?()
    }

    // MARK: - Permission

    func refreshAccessibilityPermission() {
        accessibility.refreshPermission()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Launch at login

    private func syncLaunchAtLoginAtStartup() {
        do {
            try loginItemManager.setEnabled(config.launchAtLogin)
            launchAtLoginError = nil
            if config.launchAtLogin, !loginItemManager.isEnabled {
                launchAtLoginError = "登录项尚未生效，请在「系统设置 → 通用 → 登录项」中允许 QuickCopy。"
            }
        } catch {
            launchAtLoginError = "开机自启设置失败：\(error.localizedDescription)"
            if config.launchAtLogin {
                isRevertingLaunchAtLogin = true
                config.launchAtLogin = false
                isRevertingLaunchAtLogin = false
            }
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard !isRevertingLaunchAtLogin else { return }

        do {
            try loginItemManager.setEnabled(enabled)
            if enabled, !loginItemManager.isEnabled {
                launchAtLoginError = "登录项尚未生效，请在「系统设置 → 通用 → 登录项」中允许 QuickCopy。"
            } else {
                launchAtLoginError = nil
            }
        } catch {
            launchAtLoginError = "开机自启设置失败：\(error.localizedDescription)"
            isRevertingLaunchAtLogin = true
            config.launchAtLogin = !enabled
            isRevertingLaunchAtLogin = false
        }
    }
}