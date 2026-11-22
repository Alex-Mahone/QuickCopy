import AppKit

/// 无焦点悬浮面板。
///
/// 关键点：
/// - `.nonactivatingPanel`：点击按钮时不会激活 QuickCopy，也不会抢走源 App 的焦点。
/// - 透明背景 + 无原生矩形阴影：外观完全由 SwiftUI 的胶囊决定。
/// - `.canJoinAllSpaces` + `.fullScreenAuxiliary`：在全屏 App 上也能出现。
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect = .zero) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    // 不让面板成为 key window：按钮依靠 acceptsFirstMouse 接收点击，
// 而 key window 始终留在来源 App。这样点击剪切/粘贴后，⌘X/⌘V
// 会继续由原 App 的编辑区域处理，不会被悬浮面板截走。
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}