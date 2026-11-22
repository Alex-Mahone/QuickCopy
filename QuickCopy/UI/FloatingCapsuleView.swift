import SwiftUI

/// 一次动作的即时反馈，仅用于 UI 展示。
struct CapsuleFeedback: Equatable {
    let actionID: String
    let success: Bool
}

/// 纯 UI 层：根据“动作数组 + 选区位置 + 配置”渲染一排胶囊按钮。
///
/// 这里不读取 Accessibility、不读写剪贴板、不决定窗口位置。
/// 点击按钮只把动作原样交给 `onPerform`，真正的执行由上层协调器完成。
struct FloatingCapsuleView: View {
    /// 给 SwiftUI 阴影预留的透明边距；窗口层定位时会扣除这部分。
    /// 需要略大于阴影的模糊半径 + 垂直偏移，否则阴影会在窗口边缘被硬裁切。
    static let shadowPadding: CGFloat = 8

    let actions: [QuickAction]
    /// 选区位置由窗口层用于定位，传入视图便于后续做箭头、朝向等纯视觉扩展。
    let selectionFrame: CGRect
    let configuration: CapsuleConfiguration
    let feedback: CapsuleFeedback?
    let isBusy: Bool
    let onPerform: (QuickAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(actions.indices, id: \.self) { index in
                let action = actions[index]
                // 同一视觉分组内不画线；像“搜索”这样的额外入口用细线隔开。
                if index > 0, actions[index - 1].visualGroup != action.visualGroup {
                    divider
                }
                actionButton(for: action)
            }
        }
        .padding(3 * scale)
        .modifier(CapsuleSurfaceModifier(configuration: configuration))
        .padding(Self.shadowPadding)
        .fixedSize()
        .animation(.easeOut(duration: configuration.animationDuration), value: feedback)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("QuickCopy 划词动作")
    }

    /// 整体缩放比例。窗口尺寸由 `fittingSize` 自动跟随。
    private var scale: CGFloat {
        max(0.5, configuration.scale)
    }

    private var divider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(width: 1, height: 12 * scale)
            .padding(.horizontal, 1)
    }

    private var dividerColor: Color {
        switch configuration.materialStyle {
        case .dark:
            return Color.white.opacity(0.18)
        case .light:
            return Color.black.opacity(0.10)
        default:
            return Color.primary.opacity(0.08)
        }
    }

    private var pressHighlight: Color {
        switch configuration.materialStyle {
        case .dark:
            return .white
        case .light:
            return .black
        default:
            return .primary
        }
    }

    private func actionButton(for action: QuickAction) -> some View {
        let succeeded = feedback?.actionID == action.id && feedback?.success == true
        let failed = feedback?.actionID == action.id && feedback?.success == false

        return Button {
            guard !isBusy else { return }
            onPerform(action)
        } label: {
            HStack(spacing: 4 * scale) {
                ZStack {
                    Image(systemName: action.systemImageName)
                        .opacity(succeeded || failed ? 0 : 1)

                    if succeeded {
                        Image(systemName: "checkmark")
                            .transition(.scale.combined(with: .opacity))
                    } else if failed {
                        Image(systemName: "xmark")
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .font(.system(size: 11 * scale, weight: .semibold))
                .frame(width: 13 * scale)

                // 全局“只显示图标”优先；搜索等入口本身就不显示文字。
                if action.showsTitle && !configuration.iconOnlyActions {
                    Text(action.title)
                        .font(.system(size: 11 * scale, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(foregroundColor(succeeded: succeeded, failed: failed))
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 4.5 * scale)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(CapsulePressStyle(highlight: pressHighlight))
        .disabled(!action.isEnabled || isBusy)
        .help(action.title)
        .accessibilityLabel(action.title)
    }

    private func foregroundColor(succeeded: Bool, failed: Bool) -> Color {
        if succeeded { return .green }
        if failed { return .red }
        switch configuration.materialStyle {
        case .dark:
            return Color.white.opacity(isBusy ? 0.45 : 0.92)
        case .light:
            return Color.black.opacity(isBusy ? 0.35 : 0.82)
        default:
            return .primary.opacity(isBusy ? 0.45 : 0.85)
        }
    }
}

/// 胶囊表面：macOS 26+ 使用系统原生 Liquid Glass；暗色/明亮使用固定纯色底；
/// 磨砂使用系统标准材质。
private struct CapsuleSurfaceModifier: ViewModifier {
    let configuration: CapsuleConfiguration

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: configuration.cornerRadius * max(0.5, configuration.scale),
            style: .continuous
        )

        if configuration.materialStyle.isDarkSurface {
            // 暗色：近乎不透明的深色底 + 白色内容，固定不随系统外观变化。
            content
                .background(shape.fill(Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.94)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.20), radius: 5, x: 0, y: 2)
        } else if configuration.materialStyle.isLightSurface {
            // 明亮：近乎不透明的白底 + 黑色内容，固定不随系统外观变化。
            content
                .background(shape.fill(Color(red: 0.985, green: 0.985, blue: 0.99).opacity(0.97)))
                .overlay(shape.strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
        } else if #available(macOS 26.0, *), configuration.materialStyle == .liquidGlass {
            content
                .glassEffect(.regular.interactive(), in: shape)
                .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
        } else {
            content
                .background(shape.fill(configuration.materialStyle.material))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
        }
    }
}

/// 按下时的轻微高亮，不依赖 @State，避免给纯展示视图增加状态。
private struct CapsulePressStyle: ButtonStyle {
    let highlight: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule(style: .continuous)
                    .fill(highlight.opacity(configuration.isPressed ? 0.10 : 0))
            )
    }
}