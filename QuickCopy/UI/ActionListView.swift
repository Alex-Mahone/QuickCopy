import AppKit
import SwiftUI

/// 动作列表的临时交互状态。放在窗口控制器里，避免设置视图重建时丢失。
final class ActionRowInteraction: ObservableObject {
    @Published var draggingActionID: String?
    @Published var dragPreviewTop: CGFloat = 0
    @Published var hoveredActionID: String?

    fileprivate var dragGrabOffset: CGFloat = 0
}

/// 设置页的动作列表。
///
/// 拖动时把原行隐藏，并用一整行浮层跟随鼠标；其余行实时让位。
/// 这样移动的是完整动作行（图标、文字、开关），而不是系统拖拽生成的局部截图。
struct ActionListView: View {
    @ObservedObject var config: ConfigManager
    @ObservedObject var interaction: ActionRowInteraction
    let actions: [QuickAction]

    private enum Metrics {
        static let rowHeight: CGFloat = 40
        static let rowSpacing: CGFloat = 2
        static let rowPitch = rowHeight + rowSpacing
        static let coordinateSpace = "quickcopy.actionList"
    }

    private enum RowStyle {
        case normal
        case dragPreview
    }

    var body: some View {
        VStack(spacing: Metrics.rowSpacing) {
            ForEach(orderedActions, id: \.id) { action in
                row(for: action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: Metrics.coordinateSpace)
        .overlay(alignment: .topLeading) {
            if let draggingAction {
                actionRow(draggingAction, style: .dragPreview)
                    .offset(y: interaction.dragPreviewTop)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 已启用动作按配置顺序排在前面，未启用动作按注册顺序排在后面。
    private var orderedActions: [QuickAction] {
        var result: [QuickAction] = []
        var seen = Set<String>()

        for id in config.enabledActionIDs {
            guard let action = actions.first(where: { $0.id == id }),
                  seen.insert(id).inserted else {
                continue
            }
            result.append(action)
        }

        for action in actions where !seen.contains(action.id) {
            result.append(action)
        }
        return result
    }

    private var draggingAction: QuickAction? {
        guard let id = interaction.draggingActionID else { return nil }
        return actions.first { $0.id == id }
    }

    @ViewBuilder
    private func row(for action: QuickAction) -> some View {
        let enabled = config.isActionEnabled(action.id)

        if enabled {
            actionRow(action, draggable: true)
                .opacity(interaction.draggingActionID == action.id ? 0 : 1)
        } else {
            actionRow(action)
        }
    }

    private func actionRow(_ action: QuickAction,
                           style: RowStyle = .normal,
                           draggable: Bool = false) -> some View {
        let enabled = config.isActionEnabled(action.id)
        let isPreview = style == .dragPreview
        let isHovered = !isPreview && interaction.hoveredActionID == action.id

        return HStack(spacing: 8) {
            dragArea(for: action, enabled: enabled, draggable: draggable)

            Toggle("", isOn: Binding(
                get: { config.isActionEnabled(action.id) },
                set: { config.setAction(action.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(enabled ? "关闭\(action.title)" : "启用\(action.title)")
        }
        .padding(.horizontal, 6)
        .frame(
            maxWidth: .infinity,
            minHeight: Metrics.rowHeight,
            maxHeight: Metrics.rowHeight,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isPreview
                      ? Color(nsColor: .controlBackgroundColor)
                      : (isHovered && enabled ? Color.primary.opacity(0.045) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(isPreview ? 0.12 : 0), lineWidth: 1)
        )
        .shadow(
            color: isPreview ? Color.black.opacity(0.22) : .clear,
            radius: isPreview ? 9 : 0,
            x: 0,
            y: isPreview ? 3 : 0
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            guard !isPreview, interaction.draggingActionID == nil else { return }
            if hovering {
                interaction.hoveredActionID = action.id
            } else if interaction.hoveredActionID == action.id {
                interaction.hoveredActionID = nil
            }
        }
    }

    @ViewBuilder
    private func dragArea(for action: QuickAction, enabled: Bool, draggable: Bool) -> some View {
        let content = HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 16, height: 26)
                .help(enabled ? "按住并上下拖动调整顺序" : "启用后可拖动调整顺序")
                .accessibilityHidden(true)

            Label(action.title, systemImage: action.systemImageName)

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if draggable {
            content.gesture(dragGesture(for: action))
        } else {
            content
        }
    }

    private func dragGesture(for action: QuickAction) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Metrics.coordinateSpace))
            .onChanged { value in
                if interaction.draggingActionID != action.id {
                    guard config.isActionEnabled(action.id),
                          let index = config.enabledActionIDs.firstIndex(of: action.id) else {
                        return
                    }
                    interaction.draggingActionID = action.id
                    interaction.hoveredActionID = nil
                    interaction.dragGrabOffset = value.startLocation.y - CGFloat(index) * Metrics.rowPitch
                    interaction.dragPreviewTop = CGFloat(index) * Metrics.rowPitch
                }
                updateDrag(action: action, location: value.location)
            }
            .onEnded { _ in
                guard interaction.draggingActionID == action.id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    interaction.draggingActionID = nil
                }
            }
    }

    private func updateDrag(action: QuickAction, location: CGPoint) {
        let ids = config.enabledActionIDs
        guard !ids.isEmpty, let currentIndex = ids.firstIndex(of: action.id) else { return }

        let maxTop = CGFloat(ids.count - 1) * Metrics.rowPitch
        let rawTop = location.y - interaction.dragGrabOffset
        let top = min(max(rawTop, 0), maxTop)
        interaction.dragPreviewTop = top

        let targetIndex = min(
            max(Int((top / Metrics.rowPitch).rounded()), 0),
            ids.count - 1
        )
        guard targetIndex != currentIndex else { return }

        withAnimation(.easeInOut(duration: 0.12)) {
            config.moveAction(action.id, to: targetIndex)
        }
    }
}