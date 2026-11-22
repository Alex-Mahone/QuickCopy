import AppKit
import ApplicationServices
import Combine
import Foundation

/// 辅助功能层。
///
/// 职责严格限制为：
/// 1. 监听鼠标划选 / 键盘选字；
/// 2. 通过 Accessibility API 读取选中的文字和屏幕位置；
/// 3. 过滤空选区、密码框、QuickCopy 自己、无效坐标；
/// 4. 把有效结果通过闭包交给上层。
///
/// 这一层不包含任何 UI 判断，也不知道胶囊长什么样。
///
/// CPU / 延迟策略：
/// - 不轮询选区。鼠标事件 + AX 选区变化通知驱动；鼠标抬起后立即读取，
///   只有目标 App 尚未提交新选区时才做 8ms / 20ms 两次重试。
/// - 优先复用 AX 观察器缓存的焦点元素，避免每次划词都重新查询焦点。
/// - 所有 AX 调用设置 0.25s 超时，避免某个 App 卡住主线程。
/// - 仅在没有辅助功能权限时保留一个 1.5s 的权限轮询，授权后立即停止。
final class AccessibilityService: ObservableObject {
    struct Options {
        /// 键盘选字是否弹窗，来自 ConfigManager。
        var showOnKeyboardSelection = false
    }

    /// 有效选区回调（主线程）。
    var onSelection: ((SelectionContext) -> Void)?
    /// 选区消失 / 当前选区不再有效。
    var onSelectionCleared: (() -> Void)?

    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    var options = Options()

    private(set) var isRunning = false

    private var eventMonitors: [Any] = []
    private var workspaceObserver: NSObjectProtocol?
    private var axObserver: AXObserver?
    private var observedPID: pid_t?
    private var observedAppElement: AXUIElement?
    private var observedFocusedElement: AXUIElement?

    private var pendingRead: DispatchWorkItem?
    private var permissionTimer: Timer?
    private var lastEmittedSignature: String?
    private var lastAXNotificationAt = Date.distantPast
    private var lastSource: SelectionContext.Source = .mouse

    private var mouseDownLocation: NSPoint?
    private var lastMouseUpLocation: NSPoint?
    private var isDraggingSelection = false
    private var isKeyboardSelecting = false
    private var keyboardFinishWork: DispatchWorkItem?
    /// 鼠标抬起后如果目标 App 还没提交新选区，短暂重试，而不是固定等待。
    private var mouseUpReadAttempt = 0

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// 启动监听。没有权限时会安装低频权限轮询，授权后自动开始。
    func start() {
        let trusted = AXIsProcessTrusted()
        if isTrusted != trusted {
            isTrusted = trusted
        }

        guard trusted else {
            startPermissionWatchIfNeeded()
            return
        }

        stopPermissionWatch()
        guard !isRunning else { return }
        isRunning = true
        installEventMonitors()
        installWorkspaceObserver()
        observeFrontmostApplication()
    }

    /// 用户主动停止监听（菜单栏开关）。会同时停止权限轮询。
    func stop() {
        stopPermissionWatch()
        stopMonitoring()
    }

    /// 用户点击“检查权限”或 App 被激活时调用。
    func refreshPermission() {
        let trusted = AXIsProcessTrusted()
        if isTrusted != trusted {
            isTrusted = trusted
        }

        if trusted {
            stopPermissionWatch()
            if !isRunning {
                start()
            }
        } else {
            if isRunning {
                stopMonitoring()
            }
            startPermissionWatchIfNeeded()
        }
    }

    /// 触发系统“辅助功能”授权提示。调用后 App 会出现在系统设置列表里。
    func requestPermissionPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if isTrusted != trusted {
            isTrusted = trusted
        }
        if trusted {
            stopPermissionWatch()
            start()
        }
    }

    // MARK: - Monitoring

    private func stopMonitoring() {
        guard isRunning else { return }
        isRunning = false
        pendingRead?.cancel()
        pendingRead = nil
        cancelKeyboardFinish()
        mouseDownLocation = nil
        lastMouseUpLocation = nil
        isDraggingSelection = false
        isKeyboardSelecting = false

        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()

        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }

        removeAXObserver()
        notifySelectionCleared()
    }

    private func installEventMonitors() {
        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            DispatchQueue.main.async {
                self?.handleMouseEvent(event)
            }
        }) {
            eventMonitors.append(monitor)
        }

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            DispatchQueue.main.async {
                self?.handleKeyEvent(event)
            }
        }) {
            eventMonitors.append(monitor)
        }

        // 键盘选字同样等按键松开后再读取，避免按住 Shift+方向键时每选一个字就弹一次。
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp, .flagsChanged], handler: { [weak self] event in
            DispatchQueue.main.async {
                self?.handleKeyUpEvent(event)
            }
        }) {
            eventMonitors.append(monitor)
        }
    }

    private func installWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleApplicationActivation(note)
        }
    }

    // MARK: - Permission polling (only while untrusted)

    private func startPermissionWatchIfNeeded() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if AXIsProcessTrusted() {
                self.refreshPermission()
            }
        }
    }

    private func stopPermissionWatch() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    // MARK: - Mouse / keyboard

    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // 新的点击开始：取消尚未执行的读取，避免上一轮的结果在拖选途中弹出来。
            pendingRead?.cancel()
            pendingRead = nil
            cancelKeyboardFinish()
            isKeyboardSelecting = false
            lastMouseUpLocation = nil
            mouseDownLocation = NSEvent.mouseLocation
            isDraggingSelection = false
            lastSource = .mouse
            // 新手势允许再次显示同一段选区（例如 ESC 关闭后重新双击同一句话）。
            lastEmittedSignature = nil

        case .leftMouseDragged:
            guard let start = mouseDownLocation else { return }
            let point = NSEvent.mouseLocation
            if hypot(point.x - start.x, point.y - start.y) > 3 {
                isDraggingSelection = true
            }
            lastSource = .mouse

        case .leftMouseUp:
            let wasDragging = isDraggingSelection
            let isMultiClick = event.clickCount >= 2
            let isShiftClick = event.modifierFlags.contains(.shift)

            lastMouseUpLocation = NSEvent.mouseLocation
            mouseDownLocation = nil
            isDraggingSelection = false
            mouseUpReadAttempt = 0

            if wasDragging || isMultiClick || isShiftClick {
                lastSource = .mouse
                // 松手立刻读：先不人为等待，避免每轮都固定多出 10ms。
                // 某些 App 尚未提交新选区时，读取会返回空并在下方重试。
                scheduleRead(after: 0)
            }

        default:
            break
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard isKeyboardSelectionEvent(event) else { return }
        pendingRead?.cancel()
        pendingRead = nil
        cancelKeyboardFinish()
        lastSource = .keyboard
        // 新的键盘选区手势允许再次显示同一段文字。
        lastEmittedSignature = nil
        isKeyboardSelecting = true
        // 正常路径是松键后读取；这里只做兜底，防止某些环境漏掉 keyUp。
        scheduleKeyboardFinish(after: 0.9)
    }

    /// 键盘选字结束（箭头键、⌘A 或 Shift 松开）后，等一次短暂的停顿再读取。
    private func handleKeyUpEvent(_ event: NSEvent) {
        guard isKeyboardSelecting else { return }

        let key = event.keyCode
        let selectionKeys: Set<UInt16> = [
            123, 124, 125, 126, // ← → ↓ ↑
            115, 119, 116, 121, // Home / End / Page Up / Page Down
            0,                  // A（⌘A）
            56                  // Shift
        ]

        if event.type == .flagsChanged {
            if event.modifierFlags.contains(.shift) { return }
        } else if !selectionKeys.contains(key) {
            return
        }

        // 连续敲方向键时，新的 keyDown 会取消这次收尾，不会每按一下弹一次。
        scheduleKeyboardFinish(after: 0.12)
    }

    private func scheduleKeyboardFinish(after delay: TimeInterval) {
        cancelKeyboardFinish()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isKeyboardSelecting else { return }
            self.keyboardFinishWork = nil
            self.isKeyboardSelecting = false
            self.lastSource = .keyboard
            self.scheduleRead(after: 0.03)
        }
        keyboardFinishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelKeyboardFinish() {
        keyboardFinishWork?.cancel()
        keyboardFinishWork = nil
    }

    /// 只识别“选字”类按键，不记录、不保存普通键盘输入。
    private func isKeyboardSelectionEvent(_ event: NSEvent) -> Bool {
        let key = event.keyCode
        let navigationKeys: Set<UInt16> = [
            123, // ←
            124, // →
            125, // ↓
            126, // ↑
            115, // Home
            119, // End
            116, // Page Up
            121  // Page Down
        ]

        if event.modifierFlags.contains(.shift), navigationKeys.contains(key) {
            return true
        }
        // ⌘A 全选
        if event.modifierFlags.contains(.command), key == 0 {
            return true
        }
        return false
    }

    // MARK: - AX observation

    private func observeFrontmostApplication() {
        guard isRunning else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            removeAXObserver()
            return
        }

        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            removeAXObserver()
            return
        }

        let pid = app.processIdentifier
        if observedPID == pid, axObserver != nil {
            bindFocusedElement()
            return
        }

        removeAXObserver()

        var observer: AXObserver?
        let result = AXObserverCreate(pid, quickCopyAXObserverCallback, &observer)
        guard result == .success, let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedUIElementChangedNotification as CFString,
            refcon
        )

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        axObserver = observer
        observedPID = pid
        observedAppElement = appElement
        bindFocusedElement()
    }

    private func bindFocusedElement() {
        guard let observer = axObserver, let appElement = observedAppElement else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        if let previous = observedFocusedElement {
            AXObserverRemoveNotification(
                observer,
                previous,
                kAXSelectedTextChangedNotification as CFString
            )
            observedFocusedElement = nil
        }

        guard let focused = elementAttribute(appElement, kAXFocusedUIElementAttribute) else {
            return
        }
        AXUIElementSetMessagingTimeout(focused, 0.25)

        let result = AXObserverAddNotification(
            observer,
            focused,
            kAXSelectedTextChangedNotification as CFString,
            refcon
        )
        if result == .success {
            observedFocusedElement = focused
        }
    }

    private func removeAXObserver() {
        guard let observer = axObserver else { return }

        if let focused = observedFocusedElement {
            AXObserverRemoveNotification(
                observer,
                focused,
                kAXSelectedTextChangedNotification as CFString
            )
        }
        if let appElement = observedAppElement {
            AXObserverRemoveNotification(
                observer,
                appElement,
                kAXFocusedUIElementChangedNotification as CFString
            )
        }

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        axObserver = nil
        observedPID = nil
        observedAppElement = nil
        observedFocusedElement = nil
    }

    fileprivate func handleAXNotification(name: String, element: AXUIElement) {
        guard isRunning else { return }

        if name == (kAXFocusedUIElementChangedNotification as String) {
            bindFocusedElement()
            return
        }

        guard name == (kAXSelectedTextChangedNotification as String) else { return }

        // 鼠标拖选 / 键盘按住选字期间，目标 App 会随着选区变化不断发来通知。
        // 此时不读取，等用户松开后再统一触发，避免“刚划上就弹出复制框”。
        if mouseDownLocation != nil {
            if (NSEvent.pressedMouseButtons & 0x1) == 0 {
                // 没有收到抬起事件（例如拖到屏幕外），兜底解除等待状态。
                mouseDownLocation = nil
                isDraggingSelection = false
            } else {
                return
            }
        }
        if isKeyboardSelecting { return }

        // 某些 App 一次选区变化会连发多次通知，做 30ms 合并后立即读取。
        let now = Date()
        guard now.timeIntervalSince(lastAXNotificationAt) >= 0.03 else { return }
        lastAXNotificationAt = now
        scheduleRead(after: 0.03)
    }

    private func handleApplicationActivation(_ note: Notification) {
        guard isRunning else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        notifySelectionCleared()
        cancelKeyboardFinish()
        mouseDownLocation = nil
        lastMouseUpLocation = nil
        isDraggingSelection = false
        isKeyboardSelecting = false

        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            // 打开设置窗口时 QuickCopy 自己会成为前台，停止监听自己的 AX 树。
            removeAXObserver()
        } else {
            observeFrontmostApplication()
        }
    }

    // MARK: - Reading selection

    private func scheduleRead(after delay: TimeInterval) {
        pendingRead?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performRead()
        }
        pendingRead = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func performRead() {
        guard isRunning else { return }

        guard let context = readSelection() else {
            // 个别 App 的 AX 选区更新比鼠标抬起晚几毫秒；只重试两次，
            // 避免回到固定等待，也避免真的没有选区时反复读取。
            if lastSource == .mouse, mouseUpReadAttempt < 2 {
                mouseUpReadAttempt += 1
                scheduleRead(after: mouseUpReadAttempt == 1 ? 0.008 : 0.02)
                return
            }
            notifySelectionCleared()
            return
        }
        mouseUpReadAttempt = 0

        if context.source == .keyboard, !options.showOnKeyboardSelection {
            notifySelectionCleared()
            return
        }

        guard context.signature != lastEmittedSignature else { return }
        lastEmittedSignature = context.signature
        onSelection?(context)
    }

    private func readSelection() -> SelectionContext? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }

        // 快路径：AX 观察器已经缓存了当前焦点元素（例如 Qoder 的文档区域）。
        // 直接用它读取，省掉每次重新向系统级/App 级查询焦点的 IPC。
        if observedPID == frontApp.processIdentifier,
           let cached = observedFocusedElement,
           !isSecureField(cached),
           let snapshot = selectionSnapshot(in: [cached]),
           let context = makeContext(from: snapshot, frontApp: frontApp) {
            return context
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        // 同时尝试系统级和 App 级的焦点元素：Safari 等应用在
        // 系统级焦点属性上可能返回空，但 App 级焦点是网页区域。
        var focusedElements: [AXUIElement] = []
        if let focused = elementAttribute(systemWide, kAXFocusedUIElementAttribute) {
            focusedElements.append(focused)
        }
        if let focused = elementAttribute(appElement, kAXFocusedUIElementAttribute),
           !focusedElements.contains(where: { CFEqual($0, focused) }) {
            focusedElements.append(focused)
        }
        guard !focusedElements.isEmpty else { return nil }

        // 密码框过滤：AX 的 secure text field 不读取内容。
        for element in focusedElements where isSecureField(element) {
            return nil
        }

        guard let selection = selectionSnapshot(in: focusedElements) else { return nil }

        return makeContext(from: selection, frontApp: frontApp)
    }

    private func isSecureField(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.25)
        return stringAttribute(element, kAXSubroleAttribute) == "AXSecureTextField"
    }

    private func makeContext(from selection: SelectionSnapshot,
                             frontApp: NSRunningApplication) -> SelectionContext? {
        // 优先用选中范围的精确矩形；部分 App 不提供时，
        // 鼠标选区退回鼠标抬起位置（比整个输入框的 frame 更接近文字）。
        let bounds: CGRect
        if let axRect = selection.axBounds {
            bounds = cocoaRect(fromAXRect: axRect)
        } else if lastSource == .mouse {
            bounds = mouseAnchor()
        } else if let frame = elementFrame(selection.element) {
            bounds = cocoaRect(fromAXRect: frame)
        } else {
            bounds = mouseAnchor()
        }

        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.origin.x.isFinite, bounds.origin.y.isFinite else {
            return nil
        }

        return SelectionContext(
            text: selection.text,
            bounds: bounds,
            source: lastSource,
            sourceBundleIdentifier: frontApp.bundleIdentifier,
            sourceProcessIdentifier: frontApp.processIdentifier,
            isEditable: selection.isEditable,
            pointerLocation: lastSource == .mouse ? lastMouseUpLocation : nil,
            pageURL: selection.pageURL
        )
    }

    /// 从选区元素向上查找网页地址。Safari / Chromium 的 `AXWebArea`
    /// 通常直接提供 `AXURL`；找不到时再看两三层祖先，避免拖慢热路径。
    private func webPageURL(around element: AXUIElement) -> URL? {
        var current: AXUIElement? = element
        for _ in 0..<3 {
            guard let candidate = current else { break }

            if let value = attributeValue(candidate, "AXURL") {
                if let url = value as? URL, isWebURL(url) {
                    return url
                }
                if let string = value as? String,
                   let url = URL(string: string),
                   isWebURL(url) {
                    return url
                }
            }

            if let document = stringAttribute(candidate, "AXDocument"),
               let url = URL(string: document),
               isWebURL(url) {
                return url
            }

            current = elementAttribute(candidate, kAXParentAttribute)
        }
        return nil
    }

    private func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    private struct SelectionSnapshot {
        let text: String
        /// AX 坐标（左上角原点）；nil 表示该元素不提供选区矩形。
        let axBounds: CGRect?
        let element: AXUIElement
        let isEditable: Bool
        /// 选区所在网页地址（仅 http/https）；普通 App 为 nil。
        let pageURL: URL?
    }

    /// 在焦点元素及其祖先中查找选区。
    ///
    /// WebKit（Safari、部分内嵌网页）不提供 `AXSelectedText`，
    /// 而是把选区暴露为 `AXSelectedTextMarkerRange`，需要再通过
    /// 参数化属性取文字和矩形。这里两种方式都覆盖。
    private func selectionSnapshot(in focusedElements: [AXUIElement]) -> SelectionSnapshot? {
        for focused in focusedElements {
            var element: AXUIElement? = focused

            for _ in 0..<5 {
                guard let current = element else { break }
                AXUIElementSetMessagingTimeout(current, 0.25)

                if let text = stringAttribute(current, kAXSelectedTextAttribute),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // 有的 Electron/自绘控件能给出 AXSelectedText，
                    // 但 AXBoundsForRange 返回空矩形；此时改用
                    // text marker 的选区矩形，避免退回鼠标点定位。
                    let markerFallback = selectedMarkerBounds(current)
                        .map { highlightAwareBounds($0, text: text) }
                    return SelectionSnapshot(
                        text: text,
                        axBounds: selectedRangeBounds(current) ?? markerFallback,
                        element: current,
                        isEditable: isEditableElement(current),
                        pageURL: webPageURL(around: current)
                    )
                }

                if let marker = attributeValue(current, "AXSelectedTextMarkerRange"),
                   let text = markerString(marker, in: current),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let bounds = markerBounds(marker, in: current)
                        .map { highlightAwareBounds($0, text: text) }
                    return SelectionSnapshot(
                        text: text,
                        axBounds: bounds,
                        element: current,
                        isEditable: isEditableElement(current),
                        pageURL: webPageURL(around: current)
                    )
                }

                element = elementAttribute(current, kAXParentAttribute)
            }
        }
        return nil
    }

    private func markerString(_ marker: CFTypeRef, in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            marker,
            &value
        )
        guard result == .success else { return nil }
        return value as? String
    }

    private func markerBounds(_ marker: CFTypeRef, in element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            marker,
            &value
        )
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect),
              rect.width > 0.5,
              rect.height > 0.5 else {
            return nil
        }
        return rect
    }

    private func selectedMarkerBounds(_ element: AXUIElement) -> CGRect? {
        guard let marker = attributeValue(element, "AXSelectedTextMarkerRange") else {
            return nil
        }
        return markerBounds(marker, in: element)
    }

    /// WebKit / Chromium 的 text marker 矩形常常只紧贴字形，而屏幕上绘制的
    /// 蓝色高亮是完整行高。按估算的行高向外扩展一点，让胶囊以高亮上沿为基准，
    /// 避免压住选区的蓝色阴影。公开 AX 接口拿不到高亮矩形本身，只能近似。
    private func highlightAwareBounds(_ rect: CGRect, text: String) -> CGRect {
        let lineCount = max(1, text.reduce(1) { $1.isNewline ? $0 + 1 : $0 })
        let lineHeight = rect.height / CGFloat(lineCount)
        let padding = min(max(lineHeight * 0.5, 0), 9)
        guard padding > 0.5 else { return rect }
        return CGRect(
            x: rect.minX,
            y: rect.minY - padding,
            width: rect.width,
            height: rect.height + padding * 2
        )
    }

    private func selectedRangeBounds(_ element: AXUIElement) -> CGRect? {
        guard let rangeValue = attributeValue(element, kAXSelectedTextRangeAttribute) else {
            return nil
        }

        var boundsValue: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )
        guard result == .success,
              let boundsValue,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect),
              rect.width > 0.5,
              rect.height > 0.5 else {
            return nil
        }
        return rect
    }

    private func elementFrame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = attributeValue(element, kAXPositionAttribute),
              let sizeValue = attributeValue(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private func mouseAnchor() -> CGRect {
        CGRect(origin: NSEvent.mouseLocation, size: .zero)
    }

    /// AX 的屏幕矩形以主屏左上角为原点；Cocoa 以主屏左下角为原点。
    private func cocoaRect(fromAXRect rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        guard let primary else { return rect }
        let flippedY = primary.frame.maxY - rect.maxY
        return CGRect(x: rect.minX, y: flippedY, width: rect.width, height: rect.height)
    }

    private func notifySelectionCleared() {
        guard lastEmittedSignature != nil else { return }
        lastEmittedSignature = nil
        onSelectionCleared?()
    }

    // MARK: - AX helpers

    private func attributeValue(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return result == .success ? value : nil
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attributeValue(element, name),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attributeValue(element, name) else { return nil }
        return value as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
        guard let value = attributeValue(element, name) else { return nil }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean))
        }
        return value as? Bool
    }

    /// 选区所在元素是否真正可编辑。
    ///
    /// 只看控件类型不够：网页正文、预览文档也是文本控件，但不能剪切。
    /// 这里同时检查 `AXEditable` 和 `AXSelectedText` 是否可写，
    /// 两者任一为真才认为可以安全展示剪切/粘贴。
    private func isEditableElement(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<5 {
            guard let candidate = current else { break }

            if boolAttribute(candidate, "AXEditable") == true {
                return true
            }

            var settable = DarwinBoolean(false)
            if AXUIElementIsAttributeSettable(
                candidate,
                kAXSelectedTextAttribute as CFString,
                &settable
            ) == .success, settable.boolValue {
                return true
            }

            current = elementAttribute(candidate, kAXParentAttribute)
        }
        return false
    }
}

/// C 回调不能捕获上下文，通过 refcon 取回 AccessibilityService。
private func quickCopyAXObserverCallback(_ observer: AXObserver,
                                         _ element: AXUIElement,
                                         _ notification: CFString,
                                         _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let service = Unmanaged<AccessibilityService>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String

    DispatchQueue.main.async {
        service.handleAXNotification(name: name, element: element)
    }
}