import AppKit
import SwiftUI

// MARK: - Page model

/// 设置窗口的页面。集中定义标题、图标与主题色，侧栏和页面头部共用。
enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance
    case behavior
    case actions
    case apps
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "外观"
        case .behavior: return "行为"
        case .actions: return "动作"
        case .apps: return "应用与网站"
        case .privacy: return "隐私与权限"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance:
            return "调整胶囊的材质、圆角、动效与出现位置。"
        case .behavior:
            return "控制划词监听、键盘选字与登录时启动。"
        case .actions:
            return "启用需要的动作，并拖动调整它们在胶囊中的顺序。"
        case .apps:
            return "指定哪些应用和网站不弹出 QuickCopy。"
        case .privacy:
            return "查看辅助功能授权与本地隐私说明。"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: return "paintbrush.pointed.fill"
        case .behavior: return "cursorarrow.click.2"
        case .actions: return "square.grid.2x2.fill"
        case .apps: return "app.badge.checkmark"
        case .privacy: return "lock.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .appearance: return .blue
        case .behavior: return .teal
        case .actions: return .indigo
        case .apps: return .orange
        case .privacy: return .green
        }
    }
}

/// 设置页的导航状态。窗口生命周期内保持不变，避免 SwiftUI 宏限制下的 @State。
final class SettingsNavigation: ObservableObject {
    @Published var selectedPage: SettingsPage
    @Published var hoveredPage: SettingsPage?

    init(selectedPage: SettingsPage = .appearance) {
        self.selectedPage = selectedPage
    }
}

// MARK: - Sidebar

struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var accessibility: AccessibilityService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 22)

            Text("设置")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 22)
                .padding(.bottom, 7)

            VStack(spacing: 3) {
                ForEach(SettingsPage.allCases) { page in
                    sidebarItem(for: page)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 20)

            permissionStatus
                .padding(.horizontal, 12)

            Text("QuickCopy 1.0 · 仅本地运行")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .frame(width: 198)
        .background(
            ZStack(alignment: .trailing) {
                sidebarBackground
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 1)
            }
            .ignoresSafeArea(edges: .top)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
            } else {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("QuickCopy")
                    .font(.system(size: 15, weight: .semibold))
                Text("划选即复制")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sidebarItem(for page: SettingsPage) -> some View {
        let isSelected = navigation.selectedPage == page
        let isHovered = navigation.hoveredPage == page

        return Button {
            navigation.selectedPage = page
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(page.tint.opacity(isSelected ? 0.22 : (isHovered ? 0.17 : 0.12)))
                        .frame(width: 26, height: 26)
                    Image(systemName: page.systemImage)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(page.tint)
                }

                Text(page.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                Spacer(minLength: 0)

                if isSelected {
                    Circle()
                        .fill(page.tint)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                          ? Color.primary.opacity(0.065)
                          : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                navigation.hoveredPage = page
            } else if navigation.hoveredPage == page {
                navigation.hoveredPage = nil
            }
        }
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var permissionStatus: some View {
        let trusted = accessibility.isTrusted
        let tint: Color = trusted ? .green : .orange

        return Button {
            navigation.selectedPage = .privacy
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 28, height: 28)
                    Image(systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(trusted ? "辅助功能已授权" : "需要辅助功能权限")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(trusted ? Color.primary : tint)
                    Text(trusted ? "划词监听正常" : "点击查看授权方法")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(trusted ? 0.14 : 0.24), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(trusted ? "辅助功能已授权" : "前往隐私与权限查看授权方法")
    }

    private var sidebarBackground: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.11),
                    Color.clear,
                    Color.purple.opacity(0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Page header

struct SettingsPageHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(page.tint.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: page.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(page.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(page.title)
                    .font(.system(size: 22, weight: .semibold))
                Text(page.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Group / rows

/// 一组设置项。使用统一的圆角、细边与轻阴影，保持设置页的节奏一致。
struct SettingsGroup<Content: View>: View {
    let title: String?
    let subtitle: String?
    let systemImage: String?
    let tint: Color
    let content: Content

    init(_ title: String? = nil,
         subtitle: String? = nil,
         systemImage: String? = nil,
         tint: Color = .accentColor,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 8) {
                    if let systemImage {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(tint.opacity(0.14))
                                .frame(width: 23, height: 23)
                            Image(systemName: systemImage)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(tint)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 3)
    }
}

/// 一行“标题 + 说明 + 右侧控件”。
struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let accessory: Accessory

    init(_ title: String,
         subtitle: String? = nil,
         @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)
            accessory
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
    }
}

struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.065))
            .frame(height: 1)
    }
}

struct SettingsValueChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

/// 细长的“− 数值 +”控件，比默认 Stepper 更紧凑，数值仍以 pt 显示。
struct SettingsOffsetControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accessibilityTitle: String

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemImage: "minus", title: "减小\(accessibilityTitle)") {
                value = max(range.lowerBound, value - 1)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: 15)

            Text("\(Int(value)) pt")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 46)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: 15)

            stepButton(systemImage: "plus", title: "增大\(accessibilityTitle)") {
                value = min(range.upperBound, value + 1)
            }
        }
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func stepButton(systemImage: String,
                            title: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 25, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// 带标题、滑块和当前值的设置行。
struct SettingsSliderRow: View {
    let title: String
    /// 为 nil 时只显示滑动条，不显示右侧数值。
    let valueText: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 8)
                if let valueText {
                    SettingsValueChip(text: valueText)
                }
            }

            Slider(value: $value, in: range, step: step)
                .tint(Color.accentColor)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Material chooser

/// 材质选择卡片。每块都显示一个接近实际效果的色板，选中时描边并使用强调色。
struct MaterialChoiceTile: View {
    let style: CapsuleMaterialStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                swatch
                    .frame(height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(swatchBorder, lineWidth: 0.8)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.white, Color.accentColor)
                                .padding(3)
                        }
                    }

                Text(style.title)
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .padding(7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.10)
                          : Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.70) : Color.primary.opacity(0.075),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(MaterialChoiceButtonStyle())
        .accessibilityLabel(style.title)
        .accessibilityValue(isSelected ? "已选择" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var swatchBorder: Color {
        style == .light
            ? Color.black.opacity(0.14)
            : Color.white.opacity(style == .popClip ? 0.18 : 0.24)
    }

    @ViewBuilder
    private var swatch: some View {
        switch style {
        case .liquidGlass:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.40, green: 0.56, blue: 0.96),
                        Color(red: 0.66, green: 0.42, blue: 0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient(
                    colors: [Color.white.opacity(0.38), Color.white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .regular:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.38, green: 0.48, blue: 0.66),
                        Color(red: 0.24, green: 0.30, blue: 0.44)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.regularMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .popClip:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.08))
        case .light:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(red: 0.985, green: 0.985, blue: 0.99))
        }
    }
}

private struct MaterialChoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

// MARK: - Privacy fact row

struct PrivacyFactRow: View {
    let systemImage: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 22, height: 22)
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
            }

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}