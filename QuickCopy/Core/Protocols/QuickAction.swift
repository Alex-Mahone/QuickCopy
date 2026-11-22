import Foundation

/// 胶囊动作的标准接口。
///
/// 弹窗 UI 只依赖这个协议，不依赖任何具体动作。新增动作时：
/// 1. 新建一个遵循 `QuickAction` 的类；
/// 2. 在 `AppCoordinator.registerActions()` 中 `actionManager.register(...)`；
/// 3. 在设置页的“动作”一栏勾选启用。
///
/// 不需要修改 `FloatingCapsuleView` 或 `CapsuleController`。
///
/// 后续拓展示例（伪代码，当前版本不实现翻译）：
/// ```swift
/// final class TranslateAction: QuickAction {
///     let id = "translate"
///     let title = "翻译"
///     let systemImageName = "character.book.closed"
///     var isEnabled: Bool { true }
///
///     func perform(on context: SelectionContext,
///                  completion: @escaping (QuickActionResult) -> Void) {
///         TranslationService.shared.translate(context.text) { result in
///             switch result {
///             case .success(let translated):
///                 NSPasteboard.general.clearContents()
///                 NSPasteboard.general.setString(translated, forType: .string)
///                 completion(.success)
///             case .failure(let error):
///                 completion(.failure(error.localizedDescription))
///             }
///         }
///     }
/// }
/// ```
/// 然后在 `AppCoordinator.registerActions()` 里注册：
/// `actionManager.register(TranslateAction())`。
protocol QuickAction: AnyObject {
    /// 稳定且唯一的标识，用于配置里的启用列表和反馈状态。
    var id: String { get }
    /// 按钮显示的文字，同时用于无障碍标签和 tooltip。
    var title: String { get }
    /// SF Symbol 名称。
    var systemImageName: String { get }
    /// 动作当前是否可用。默认 true，动作可以按运行状态临时关闭。
    var isEnabled: Bool { get }
    /// 当前选区是否满足动作的展示条件。默认 true。
    /// 例如“打开链接”只在整段选区是网页链接时返回 true。
    func isAvailable(for context: SelectionContext) -> Bool
    /// 视觉分组：相邻且在同一个分组的按钮之间不画分隔线。
    /// 默认 0；像“搜索”这类额外入口可以放到 1，用一条细线隔开。
    var visualGroup: Int { get }
    /// 是否在图标右侧显示文字。默认 true；额外入口可以只显示图标。
    var showsTitle: Bool { get }
    /// 是否只对可编辑文本展示。剪切/粘贴/删除为 true；
    /// 网页正文等只读选区会自动隐藏这些按钮。
    var requiresEditableText: Bool { get }
    /// 动作的触发回调。必须在 completion 中回调结果；
    /// 同步动作可以直接回调，异步动作（如网络翻译）在完成后回调即可。
    func perform(on context: SelectionContext,
                 completion: @escaping (QuickActionResult) -> Void)
}

extension QuickAction {
    var isEnabled: Bool { true }
    func isAvailable(for context: SelectionContext) -> Bool { true }
    var visualGroup: Int { 0 }
    var showsTitle: Bool { true }
    var requiresEditableText: Bool { false }
}