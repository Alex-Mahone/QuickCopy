import AppKit
import QuartzCore
import SwiftUI

/// 悬浮胶囊的窗口控制器。
///
/// 负责：
/// - 根据选区坐标把窗口放在选区上方（空间不足时翻到下方）；
/// - 将动作、配置快照交给 SwiftUI 渲染；
/// - 点击外部、ESC、切换 App、选区消失时关闭；
/// - 复制成功后的对勾反馈与短暂停留。
///
/// 不负责读取选区、不负责执行动作，保持与业务层解耦。
final class CapsuleController {
    enum HideReason {
        case clickOutside
        case escape
        case selectionCleared
        case applicationChanged
        case completed
        case manual
    }

    /// 按钮点击后由协调器接管执行。
    var onPerform: ((QuickAction, SelectionContext) -> Void)?

    private let panel = FloatingPanel()
    private let hostingView: CapsuleHostingView<FloatingCapsuleView>

    private var context: SelectionContext?
    private var actions: [QuickAction] = []
    private var configuration: CapsuleConfiguration = .default
    private var feedback: CapsuleFeedback?
    private var isBusy = false

    private(set) var isShowing = false

    private var suppressSignature: String?
    private var suppressSince = Date.distantPast
    private static let suppressWindow: TimeInterval = 0.6

    private var dismissMonitors: [Any] = []
    private var autoHideWorkItem: DispatchWorkItem?
    private var workspaceObserver: NSObjectProtocol?
    private var animationGeneration = 0

    init() {
        let initialView = FloatingCapsuleView(
            actions: [],
            selectionFrame: .zero,
            configuration: .default,
            feedback: nil,
            isBusy: false,
            onPerform: { _ in }
        )
        let hosting = CapsuleHostingView(rootView: initialView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        self.hostingView = hosting

        panel.contentView = hosting

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isShowing else { return }
            guard let front = NSWorkspace.shared.frontmostApplication,
                  front.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return
            }
            self.hide(reason: .applicationChanged)
        }
    }

    deinit {
        autoHideWorkItem?.cancel()
        removeDismissMonitors()
        panel.orderOut(nil)
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    // MARK: - Public API

    func show(context: SelectionContext,
              actions: [QuickAction],
              configuration: CapsuleConfiguration) {
        guard !actions.isEmpty else { return }

        // 刚刚因点击外部/复制完成而关闭的同一选区，短时间内不再弹。
        if context.signature == suppressSignature,
           Date().timeIntervalSince(suppressSince) < Self.suppressWindow {
            return
        }

        // AX 通知可能对同一选区重复触发；已经显示时不要重置对勾反馈。
        if isShowing, context.signature == self.context?.signature {
            return
        }

        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil

        suppressSignature = nil
        self.context = context
        self.actions = actions
        self.configuration = configuration
        self.feedback = nil
        self.isBusy = false

        render()
        let target = targetFrame(for: context)
        guard target.width > 2, target.height > 2 else { return }

        if isShowing {
            panel.orderFrontRegardless()
            animate(to: target)
            installDismissMonitors()
        } else {
            present(at: target)
        }
    }

    func updateConfiguration(_ configuration: CapsuleConfiguration) {
        self.configuration = configuration
        guard isShowing else { return }
        render()
        if let context {
            animate(to: targetFrame(for: context))
        }
    }

    /// 启动时先把按钮视图搭好并完成首次排版，避免第一次划词时
    /// SwiftUI / Liquid Glass 的初始化耗时叠加到弹出延迟上。
    /// 面板不会显示，用户看不到任何东西。
    func prewarm(actions: [QuickAction], configuration: CapsuleConfiguration) {
        guard !isShowing, !actions.isEmpty else { return }
        self.actions = actions
        self.configuration = configuration
        render()
        hostingView.displayIfNeeded()
        self.actions = []
    }

    func showFeedback(actionID: String, success: Bool) {
        guard isShowing else { return }
        feedback = CapsuleFeedback(actionID: actionID, success: success)
        isBusy = false
        render()
        if let context {
            animate(to: targetFrame(for: context))
        }

        autoHideWorkItem?.cancel()
        let delay: TimeInterval = success ? 0.8 : 1.25
        let work = DispatchWorkItem { [weak self] in
            self?.hide(reason: .completed)
        }
        autoHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 选区本身消失了（文字取消选中、焦点进入非文本控件等）。
    func selectionDidClear() {
        suppressSignature = nil
        suppressSince = .distantPast

        // 已经复制成功时，让对勾短暂停留，不要立刻闪掉。
        if feedback != nil {
            return
        }

        hide(reason: .selectionCleared)
        suppressSignature = nil
        suppressSince = .distantPast
    }

    func hide(reason: HideReason = .manual) {
        guard isShowing else { return }

        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil

        if let context {
            suppressSignature = context.signature
            suppressSince = Date()
        }

        removeDismissMonitors()

        animationGeneration += 1
        let generation = animationGeneration
        let duration = max(0.04, configuration.animationDuration)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.finishHide()
        }
    }

    // MARK: - Rendering & layout

    private func render() {
        hostingView.rootView = FloatingCapsuleView(
            actions: actions,
            selectionFrame: context?.bounds ?? .zero,
            configuration: configuration,
            feedback: feedback,
            isBusy: isBusy,
            onPerform: { [weak self] action in
                self?.handleTap(action)
            }
        )
        hostingView.layoutSubtreeIfNeeded()

        let size = hostingView.fittingSize
        if size.width > 2, size.height > 2 {
            panel.setContentSize(size)
        }
    }

    private func present(at target: NSRect) {
        animationGeneration += 1

        // 瞬时显示：不做淡入和位移，松开后读取到选区就立刻可见。
        panel.setFrame(target, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        isShowing = true
        installDismissMonitors()
    }

    private func animate(to target: NSRect) {
        animationGeneration += 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = max(0.04, configuration.animationDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    private func finishHide() {
        panel.orderOut(nil)
        panel.alphaValue = 0
        isShowing = false
        isBusy = false
        feedback = nil
        context = nil
        actions = []
        removeDismissMonitors()
    }

    /// 计算窗口 frame。窗口比胶囊多出阴影透明边距，所以定位时要扣掉。
    private func targetFrame(for context: SelectionContext) -> NSRect {
        let padding = FloatingCapsuleView.shadowPadding
        let windowSize = panel.frame.size
        let capsuleWidth = max(1, windowSize.width - padding * 2)
        let capsuleHeight = max(1, windowSize.height - padding * 2)
        let selection = context.bounds
        let offset = configuration.popupOffset

        guard let screen = screen(containing: selection) else {
            return NSRect(origin: selection.origin, size: windowSize)
        }
        let visible = screen.visibleFrame
        let margin: CGFloat = 8

        // 水平方向仍锚定鼠标松开位置，手不用横向移动；
        // 垂直方向以整个选区的上边缘为准，避免多行选区时
        // 胶囊跟着松开点落在选区内部、挡住文字。
        // 键盘选区没有光标位置，水平居中于选中文段。
        let anchorX: CGFloat
        if let pointer = context.pointerLocation {
            anchorX = pointer.x
        } else {
            anchorX = selection.midX
        }

        var capsuleX = anchorX - capsuleWidth / 2 + offset.width
        var capsuleY = selection.maxY + offset.height

        // 上方空间不足时翻到整个选区下方，而不是翻到松开点下方。
        if capsuleY + capsuleHeight + margin > visible.maxY {
            capsuleY = selection.minY - offset.height - capsuleHeight
        }

        capsuleX = min(max(capsuleX, visible.minX + margin), visible.maxX - capsuleWidth - margin)
        capsuleY = min(max(capsuleY, visible.minY + margin), visible.maxY - capsuleHeight - margin)

        return NSRect(
            x: capsuleX - padding,
            y: capsuleY - padding,
            width: windowSize.width,
            height: windowSize.height
        )
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        let point = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    // MARK: - Interaction

    private func handleTap(_ action: QuickAction) {
        guard !isBusy, let context else { return }
        isBusy = true
        feedback = nil
        render()
        onPerform?(action, context)
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isShowing else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide(reason: .clickOutside)
                }
            }
        }) {
            dismissMonitors.append(monitor)
        }

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async {
                self?.hide(reason: .escape)
            }
        }) {
            dismissMonitors.append(monitor)
        }

        // 面板成为 key window 时，ESC 由本地监视器吃掉，避免系统提示音。
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            DispatchQueue.main.async {
                self?.hide(reason: .escape)
            }
            return nil
        }) {
            dismissMonitors.append(monitor)
        }
    }

    private func removeDismissMonitors() {
        for monitor in dismissMonitors {
            NSEvent.removeMonitor(monitor)
        }
        dismissMonitors.removeAll()
    }
}

/// 让悬浮面板在非激活状态下也能响应“第一次点击”，
/// 否则从源 App 直接点按钮时，第一次点击可能只被用来激活窗口而不触发按钮。
private final class CapsuleHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
