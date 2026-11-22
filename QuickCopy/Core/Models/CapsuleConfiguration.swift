import CoreGraphics
import SwiftUI

/// 胶囊可用的外观样式。配置层只存枚举，SwiftUI/UI 层再映射为具体绘制，
/// 这样后续增加样式时不需要改动悬浮窗代码。
enum CapsuleMaterialStyle: String, CaseIterable, Identifiable, Codable {
    /// macOS 26 及以上使用系统原生 Liquid Glass；旧系统自动退回磨砂。
    case liquidGlass
    /// 系统标准材质的磨砂效果。
    case regular
    /// 固定深色表面 + 白色前景，不随系统外观变化。
    case dark
    /// 固定浅色表面 + 黑色前景，类似白底黑字的明亮样式。
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquidGlass:
            return "玻璃"
        case .regular:
            return "磨砂"
        case .dark:
            return "暗色"
        case .light:
            return "明亮"
        }
    }

    /// 固定深色样式，不随系统亮/暗模式切换。
    var isDarkSurface: Bool {
        self == .dark
    }

    /// 固定浅色样式，不随系统亮/暗模式切换。
    var isLightSurface: Bool {
        self == .light
    }

    /// 非 Liquid Glass 材质，或旧系统上的回退材质。
    /// `.dark` / `.light` 不使用这里的 Material，由 UI 层绘制纯色底。
    var material: Material {
        switch self {
        case .liquidGlass, .regular:
            return .regularMaterial
        case .dark, .light:
            return .ultraThinMaterial
        }
    }
}

/// 悬浮胶囊的纯视觉配置快照。
///
/// ConfigManager 每次变化时生成新的快照传给 UI 层，
/// UI 层不需要认识 UserDefaults，也不需要知道配置如何持久化。
struct CapsuleConfiguration: Equatable {
    /// 胶囊高度有限，圆角超过这个值后外观不再变化。
    static let maximumCornerRadius: CGFloat = 18

    var cornerRadius: CGFloat
    /// 整个胶囊的缩放比例，同时作用于字号、内边距、图标和圆角。
    var scale: CGFloat
    var materialStyle: CapsuleMaterialStyle
    var animationDuration: Double
    var popupOffset: CGSize
    /// 动作按钮是否只显示图标。开启后剪切/复制/粘贴隐藏文字，悬停仍显示名称。
    var iconOnlyActions: Bool

    static let scaleRange: ClosedRange<CGFloat> = 0.8...1.5

    static let `default` = CapsuleConfiguration(
        cornerRadius: maximumCornerRadius,
        scale: 1,
        materialStyle: .liquidGlass,
        animationDuration: 0.12,
        popupOffset: CGSize(width: 0, height: 8),
        iconOnlyActions: false
    )
}