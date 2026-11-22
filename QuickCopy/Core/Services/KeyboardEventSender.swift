import AppKit
import CoreGraphics

/// 把标准编辑按键定向发给来源 App。
///
/// 胶囊是 non-activating 面板，点击按钮不会把 QuickCopy 变成前台 App；
/// 但面板会短暂成为 key window，来源 App 的编辑区域因此暂时不是 key
/// window，直接投递 ⌘X/⌘V/Delete 可能没人处理。这里先把来源 App 重新激活，
/// 等 key window 回到它的编辑区域，再发送按键事件。
enum KeyboardEventSender {
    enum Key: CGKeyCode {
        case cut = 7      // X
        case paste = 9    // V
        case delete = 51  // Delete（退格键）

        /// 编辑命令的修饰键；删除选区不需要修饰键。
        var flags: CGEventFlags {
            switch self {
            case .cut, .paste:
                return .maskCommand
            case .delete:
                return []
            }
        }
    }

    /// 发送一个编辑按键。completion(false) 表示目标进程已退出或无法创建事件。
    static func send(_ key: Key,
                     to pid: Int32,
                     completion: @escaping (Bool) -> Void) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            completion(false)
            return
        }

        // 来源 App 本来就是前台 App；这里只是把 key window 重新交还给它。
        app.activate(options: [.activateAllWindows])

        // 让激活和 key window 切换先走完一个短周期，再投递按键。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard !app.isTerminated else {
                completion(false)
                return
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                completion(false)
                return
            }
            completion(post(key))
        }
    }

    private static func post(_ key: Key) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false) else {
            return false
        }

        keyDown.flags = key.flags
        keyUp.flags = key.flags

        keyDown.post(tap: .cghidEventTap)
        // 极短的间隔让目标 App 先处理 keyDown，再收到 keyUp。
        Thread.sleep(forTimeInterval: 0.006)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}