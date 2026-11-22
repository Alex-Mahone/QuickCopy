import Foundation

/// 一次有效的文字选区。
///
/// - `text` 原样保存用户选中的文字（不 trim，复制时保持原内容）。
/// - `bounds` 使用 Cocoa 屏幕坐标（原点在主屏左下角，单位 pt），可直接用于 NSWindow 定位。
/// - `source` 记录选区来自鼠标还是键盘，用于落实“键盘选字默认不弹窗”的配置。
/// - `pointerLocation` 是鼠标抬起位置（Cocoa 坐标）；鼠标选区用它定位胶囊，
///   让弹窗靠近光标，减少移动距离。
struct SelectionContext: Equatable {
    enum Source: String {
        case mouse
        case keyboard
    }

    let text: String
    let bounds: CGRect
    let source: Source
    let capturedAt: Date
    /// 选区所属 App 的 bundle id，用于应用排除列表。
    let sourceBundleIdentifier: String?
    /// 选区所属 App 的进程号。剪切/粘贴要先把标准快捷键定向发给它，
    /// 避免胶囊面板短暂成为 key window 时按键落到错误的目标。
    let sourceProcessIdentifier: Int32?
    /// 选区是否位于可编辑文本中。网页正文、预览类文本不可编辑，
    /// 此时不展示剪切/粘贴，避免点击后只得到失败提示。
    let isEditable: Bool
    /// 鼠标松开时的光标位置；键盘选区为 nil。
    let pointerLocation: CGPoint?
    /// 选区所在网页的 URL（仅 http/https）。用于网站排除列表；
    /// 普通桌面应用没有网页地址时为 nil。
    let pageURL: URL?

    init(text: String,
         bounds: CGRect,
         source: Source,
         capturedAt: Date = Date(),
         sourceBundleIdentifier: String? = nil,
         sourceProcessIdentifier: Int32? = nil,
         isEditable: Bool = false,
         pointerLocation: CGPoint? = nil,
         pageURL: URL? = nil) {
        self.text = text
        self.bounds = bounds
        self.source = source
        self.capturedAt = capturedAt
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceProcessIdentifier = sourceProcessIdentifier
        self.isEditable = isEditable
        self.pointerLocation = pointerLocation
        self.pageURL = pageURL
    }

    /// 用于去重：同样的文字 + 同样的屏幕位置视为同一次选区。
    /// 避免 AX 通知与鼠标事件重复触发时反复重建悬浮窗。
    var signature: String {
        let x = Int(bounds.origin.x.rounded())
        let y = Int(bounds.origin.y.rounded())
        let width = Int(bounds.width.rounded())
        let height = Int(bounds.height.rounded())
        return "\(text.hashValue)-\(x)-\(y)-\(width)-\(height)"
    }
}