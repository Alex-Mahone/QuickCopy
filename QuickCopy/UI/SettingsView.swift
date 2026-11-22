import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 设置窗口内容。
///
/// 侧栏只切换页面；每个页面都把可观察配置展示出来并写回 ConfigManager。
/// 这里不直接操作 Accessibility、剪贴板或胶囊窗口。
struct SettingsView: View {
    @ObservedObject var config: ConfigManager
    @ObservedObject var accessibility: AccessibilityService
    @ObservedObject var actionManager: ActionManager
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var navigation: SettingsNavigation
    let actionInteraction: ActionRowInteraction

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(navigation: navigation, accessibility: accessibility)
            content
        }
        .background(SettingsBackground())
    }

    // MARK: - Content shell

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPageHeader(page: navigation.selectedPage)
                pageContent
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(navigation.selectedPage)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch navigation.selectedPage {
        case .appearance:
            appearancePage
        case .behavior:
            behaviorPage
        case .actions:
            actionsPage
        case .apps:
            appsPage
        case .privacy:
            privacyPage
        }
    }

    // MARK: - Appearance

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            CapsulePreviewCard(
                actions: previewActions,
                configuration: config.capsuleConfiguration
            )

            SettingsGroup(
                "胶囊样式",
                subtitle: "材质与尺寸会立即同步到上方预览。",
                systemImage: "capsule",
                tint: .blue
            ) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("材质")
                        .font(.system(size: 12.5, weight: .medium))

                    HStack(spacing: 8) {
                        ForEach(CapsuleMaterialStyle.allCases) { style in
                            MaterialChoiceTile(style: style, isSelected: config.materialStyle == style) {
                                config.materialStyle = style
                            }
                        }
                    }
                }

                SettingsFootnote("玻璃使用 macOS 26 的 Liquid Glass，需要 macOS 26 或更高；旧系统会自动回退为磨砂。磨砂使用系统标准材质；暗色/明亮是固定深色/浅色样式，不随系统亮暗模式变化。")

                SettingsDivider()

                SettingsSliderRow(
                    title: "胶囊大小",
                    valueText: "\(Int((config.capsuleScale * 100).rounded()))%",
                    value: $config.capsuleScale,
                    range: Double(CapsuleConfiguration.scaleRange.lowerBound)...Double(CapsuleConfiguration.scaleRange.upperBound),
                    step: 0.05
                )

                SettingsDivider()

                SettingsSliderRow(
                    title: "胶囊圆角",
                    valueText: nil,
                    value: $config.cornerRadius,
                    range: 0...Double(CapsuleConfiguration.maximumCornerRadius),
                    step: 1
                )

                SettingsDivider()

                SettingsToggleRow(
                    "动作按钮只显示图标",
                    subtitle: "开启后剪切、复制、粘贴、删除不再显示文字；悬停按钮仍会显示名称。",
                    isOn: $config.iconOnlyActions
                )
            }

            SettingsGroup(
                "动效与位置",
                subtitle: "出现为瞬时显示，这里控制消失和位置变化的节奏。",
                systemImage: "sparkles",
                tint: .indigo
            ) {
                SettingsSliderRow(
                    title: "动画时长",
                    valueText: String(format: "%.2f s", config.animationDuration),
                    value: $config.animationDuration,
                    range: 0.05...0.5,
                    step: 0.01
                )

                SettingsDivider()

                SettingsRow("水平偏移", subtitle: "正数向右") {
                    SettingsOffsetControl(
                        value: $config.popupOffsetX,
                        range: -20...60,
                        accessibilityTitle: "水平偏移"
                    )
                }

                SettingsRow("垂直偏移", subtitle: "正数向上") {
                    SettingsOffsetControl(
                        value: $config.popupOffsetY,
                        range: -20...60,
                        accessibilityTitle: "垂直偏移"
                    )
                }

                SettingsFootnote("胶囊默认出现在鼠标松开位置的正上方；键盘选区则居中于文段上方。上方空间不足时会自动翻到下方。")
            }

            HStack(spacing: 12) {
                SettingsFootnote("所有外观修改都会立即生效，无需重启。")
                Spacer(minLength: 12)
                Button("恢复默认外观") {
                    config.resetAppearance()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Behavior

    /// 外观预览使用普通文字选区，不展示只在网页链接选区出现的动作。
    private var previewActions: [QuickAction] {
        let context = SelectionContext(
            text: "示例文字",
            bounds: .zero,
            source: .mouse,
            isEditable: true
        )
        return actionManager.enabledActions(for: config.enabledActionIDs)
            .filter { $0.isAvailable(for: context) }
    }

    private var behaviorPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(
                "划词监听",
                subtitle: "控制 QuickCopy 何时读取选区并弹出胶囊。",
                systemImage: "cursorarrow.click",
                tint: .teal
            ) {
                SettingsToggleRow(
                    "启用划词监听",
                    subtitle: "关闭后不会读取任何选区，也不会弹出胶囊。",
                    isOn: Binding(
                        get: { coordinator.isMonitoringEnabled },
                        set: { coordinator.setMonitoringEnabled($0) }
                    )
                )

                SettingsDivider()

                SettingsToggleRow(
                    "键盘 Shift+方向键选字时也弹出",
                    subtitle: "默认不弹出，避免输入过程中打扰。",
                    isOn: $config.showOnKeyboardSelection
                )

                SettingsFootnote("鼠标拖选、双击选词、三击选段默认始终触发；键盘选字只在开启上一项后响应。")
            }

            SettingsGroup(
                "启动",
                subtitle: "让 QuickCopy 在登录后自动待命。",
                systemImage: "power",
                tint: .orange
            ) {
                SettingsToggleRow(
                    "登录时启动 QuickCopy",
                    isOn: $config.launchAtLogin
                )

                if let error = coordinator.launchAtLoginError {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                } else if config.launchAtLogin {
                    SettingsFootnote("已通过 macOS SMAppService 注册。开发构建不在 /Applications 时，系统可能拒绝注册。")
                } else {
                    SettingsFootnote("关闭后需要手动从「应用程序」或菜单栏启动 QuickCopy。")
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsPage: some View {
        SettingsGroup(
            "动作顺序",
            subtitle: "已启用 \(enabledActionCount) 个动作，顺序会同步到胶囊。",
            systemImage: "line.3.horizontal",
            tint: .indigo
        ) {
            if actionManager.actions.isEmpty {
                Text("还没有注册动作。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ActionListView(
                    config: config,
                    interaction: actionInteraction,
                    actions: actionManager.actions
                )
            }

            SettingsDivider()

            SettingsFootnote("按住一行上下拖动即可调整顺序，左侧三条横线是拖动手柄。关闭的动作排在后面，重新开启后追加到末尾。")

            SettingsFootnote("「打开链接」只在整段选区就是一个网页链接时出现；支持 http/https、www 和裸域名，点击后交给系统默认浏览器打开。")

            SettingsFootnote("剪切、粘贴会向来源 App 发送标准 ⌘X/⌘V；删除只发送退格键，不写入剪贴板；搜索调用系统的 Safari 搜索服务，与文本右键菜单里的搜索一致。")
        }
    }

    private var enabledActionCount: Int {
        actionManager.enabledActions(for: config.enabledActionIDs).count
    }

    // MARK: - Excluded apps

    private var appsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(
                "不启用的应用",
                subtitle: config.excludedAppBundleIDs.isEmpty
                    ? "当前在所有应用中启用"
                    : "已排除 \(config.excludedAppBundleIDs.count) 个应用",
                systemImage: "app.badge.checkmark",
                tint: .orange
            ) {
                if config.excludedAppBundleIDs.isEmpty {
                    emptyExclusions
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(config.excludedAppBundleIDs.enumerated()), id: \.offset) { index, bundleID in
                            if index > 0 {
                                SettingsDivider()
                            }
                            excludedAppRow(bundleID: bundleID)
                        }
                    }

                    SettingsDivider()

                    HStack {
                        Button {
                            chooseExcludedApps()
                        } label: {
                            Label("添加应用…", systemImage: "plus")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .controlSize(.small)

                        Spacer()

                        Text("在这些应用中划词不会弹出胶囊。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsGroup(
                "不启用的网站",
                subtitle: config.excludedSiteHosts.isEmpty
                    ? "当前在所有网站启用"
                    : "已排除 \(config.excludedSiteHosts.count) 个网站",
                systemImage: "globe",
                tint: .blue
            ) {
                if config.excludedSiteHosts.isEmpty {
                    emptySiteExclusions
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(config.excludedSiteHosts.enumerated()), id: \.offset) { index, host in
                            if index > 0 {
                                SettingsDivider()
                            }
                            excludedSiteRow(host: host)
                        }
                    }

                    SettingsDivider()

                    HStack {
                        Button {
                            chooseExcludedSite()
                        } label: {
                            Label("添加网站…", systemImage: "plus")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .controlSize(.small)

                        Spacer()

                        Text("域名和它的子域名都会排除。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsFootnote("从网页区域读取当前网址进行匹配，适用于 Safari、Chrome、Edge 等浏览器和内嵌网页；不会记录浏览历史或选中的文字。个别不暴露网页地址的应用无法按网站排除。")
            }
        }
    }

    private var emptyExclusions: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.11))
                    .frame(width: 48, height: 48)
                Image(systemName: "app.badge.checkmark")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.orange)
            }

            Text("尚未添加应用")
                .font(.system(size: 12.5, weight: .semibold))

            Text("QuickCopy 目前会在所有应用中响应划词。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button {
                chooseExcludedApps()
            } label: {
                Label("添加应用…", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .controlSize(.small)
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func excludedAppRow(bundleID: String) -> some View {
        HStack(spacing: 10) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 26, height: 26)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 17))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(appName(for: bundleID))
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                config.removeExcludedApp(bundleID: bundleID)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("从排除列表移除")
        }
        .padding(.vertical, 7)
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else {
            return bundleID
        }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    private func chooseExcludedApps() {
        let panel = NSOpenPanel()
        panel.title = "选择不启用 QuickCopy 的应用"
        panel.message = "在选中的应用里划词时不会弹出胶囊。"
        panel.prompt = "添加"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            config.addExcludedApp(bundleID: bundleID)
        }
    }

    private var emptySiteExclusions: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.10))
                    .frame(width: 48, height: 48)
                Image(systemName: "globe")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.blue)
            }

            Text("尚未添加网站")
                .font(.system(size: 12.5, weight: .semibold))

            Text("QuickCopy 目前会在所有网站的网页里响应划词。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button {
                chooseExcludedSite()
            } label: {
                Label("添加网站…", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .controlSize(.small)
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func excludedSiteRow(host: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.blue.opacity(0.10))
                    .frame(width: 26, height: 26)
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(host)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text("该域名及其子域名")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                config.removeExcludedSite(host)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("从网站排除列表移除")
        }
        .padding(.vertical, 7)
    }

    private func chooseExcludedSite() {
        let alert = NSAlert()
        alert.messageText = "添加不启用的网站"
        alert.informativeText = "输入域名或网址，例如 github.com 或 https://example.com。该域名及其子域名下划词不会弹出胶囊。"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "example.com"
        field.font = .systemFont(ofSize: 13)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard config.addExcludedSite(field.stringValue) else {
            NSSound.beep()
            let warning = NSAlert()
            warning.messageText = "网站地址无法识别"
            warning.informativeText = "请输入域名或网址，例如 example.com 或 https://example.com。"
            warning.addButton(withTitle: "好")
            warning.runModal()
            return
        }
    }

    // MARK: - Privacy

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            permissionCard

            SettingsGroup(
                "隐私说明",
                subtitle: "QuickCopy 的权限边界",
                systemImage: "hand.raised.fill",
                tint: .green
            ) {
                VStack(alignment: .leading, spacing: 11) {
                    PrivacyFactRow(
                        systemImage: "accessibility",
                        tint: .green,
                        text: "辅助功能权限用于读取当前选区文字与位置；不会修改系统设置。"
                    )
                    PrivacyFactRow(
                        systemImage: "keyboard",
                        tint: .teal,
                        text: "为了区分鼠标划选和键盘选字，会监听少量选择类按键（Shift+方向键、⌘A），不记录、不保存普通键盘输入。"
                    )
                    PrivacyFactRow(
                        systemImage: "wifi.slash",
                        tint: .blue,
                        text: "仅在本机运行，不联网、不上传选中文字。"
                    )
                    PrivacyFactRow(
                        systemImage: "globe",
                        tint: .cyan,
                        text: "网站排除只在本机把当前网页域名与排除列表比较，不保存浏览记录。"
                    )
                    PrivacyFactRow(
                        systemImage: "doc.on.clipboard",
                        tint: .indigo,
                        text: "不拦截系统 ⌘C/⌘X/⌘V；只有点击胶囊里的剪切/复制时才会改变剪贴板，删除不会写入剪贴板。"
                    )
                    PrivacyFactRow(
                        systemImage: "safari",
                        tint: .orange,
                        text: "搜索会把查询词交给系统的 Safari 搜索服务，由浏览器打开结果页。"
                    )
                }
            }

            aboutCard
        }
    }

    private var permissionCard: some View {
        let trusted = accessibility.isTrusted
        let tint: Color = trusted ? .green : .orange

        return VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(trusted ? "辅助功能已授权" : "尚未获得辅助功能权限")
                        .font(.system(size: 14, weight: .semibold))
                    Text(trusted
                         ? "QuickCopy 可以读取当前选中的文字与选区位置。"
                         : "需要这项权限才能读取选区并弹出胶囊。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            if !trusted {
                SettingsDivider()

                Text("请在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 QuickCopy，然后回到这里点「重新检查」。macOS 有时需要重启 QuickCopy 才能识别新授权。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("重新检查") {
                    coordinator.refreshAccessibilityPermission()
                }
                .controlSize(.small)

                Button("打开系统设置") {
                    coordinator.openAccessibilitySettings()
                }
                .controlSize(.small)

                Spacer()

                if trusted {
                    Label("权限正常", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(trusted ? 0.055 : 0.075))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(trusted ? 0.16 : 0.24), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 10, x: 0, y: 3)
    }

    private var aboutCard: some View {
        HStack(spacing: 11) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("QuickCopy 1.0")
                    .font(.system(size: 12, weight: .semibold))
                Text("仅在本机运行，不保存选中的文字。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("本地运行")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Color.primary.opacity(0.05),
                    in: Capsule(style: .continuous)
                )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.055), lineWidth: 1)
        )
    }
}

// MARK: - Live preview

/// 设置页顶部的胶囊实时预览。复用真正的 FloatingCapsuleView，
/// 因此材质、圆角、图标模式和动作顺序都会即时反映出来。
private struct CapsulePreviewCard: View {
    let actions: [QuickAction]
    let configuration: CapsuleConfiguration

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.13, blue: 0.25),
                    Color(red: 0.08, green: 0.19, blue: 0.23),
                    Color(red: 0.20, green: 0.11, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.30, green: 0.55, blue: 0.96).opacity(0.34))
                .frame(width: 240, height: 240)
                .blur(radius: 70)
                .offset(x: -170, y: -46)

            Circle()
                .fill(Color(red: 0.86, green: 0.46, blue: 0.42).opacity(0.20))
                .frame(width: 210, height: 210)
                .blur(radius: 72)
                .offset(x: 190, y: 58)

            // 预览背景使用固定深色渐变，让玻璃、磨砂和纯色样式都能看出层次。
            if actions.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "capsule")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.48))
                    Text("未启用动作")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.70))
                    Text("到「动作」页开启需要的按钮")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
            } else {
                FloatingCapsuleView(
                    actions: actions,
                    selectionFrame: .zero,
                    configuration: configuration,
                    feedback: nil,
                    isBusy: false,
                    onPerform: { _ in }
                )
                .allowsHitTesting(false)
            }
        }
        .frame(height: 154)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 5) {
                Image(systemName: "eye")
                    .font(.system(size: 9, weight: .semibold))
                Text("实时预览")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.55))
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("胶囊实时预览")
    }
}

// MARK: - Window background

private struct SettingsBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color(red: 0.26, green: 0.45, blue: 0.95).opacity(0.045),
                    Color.clear,
                    Color.purple.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.045))
                .frame(width: 340, height: 340)
                .blur(radius: 100)
                .offset(x: 250, y: -240)
        }
        .ignoresSafeArea()
    }
}