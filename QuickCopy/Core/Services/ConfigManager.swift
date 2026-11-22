import Combine
import CoreGraphics
import Foundation

/// 配置层。
///
/// 所有可调项集中在这里，并使用 @Published 驱动 SwiftUI 设置页；
/// 每个属性变化后立即写入 UserDefaults。UI 层只拿 `capsuleConfiguration`
/// 快照，不直接接触持久化细节。
final class ConfigManager: ObservableObject {
    private enum Key {
        static let cornerRadius = "quickcopy.cornerRadius"
        static let capsuleScale = "quickcopy.capsuleScale"
        static let material = "quickcopy.material"
        static let animationDuration = "quickcopy.animationDuration"
        static let popupOffsetX = "quickcopy.popupOffsetX"
        static let popupOffsetY = "quickcopy.popupOffsetY"
        static let showOnKeyboardSelection = "quickcopy.showOnKeyboardSelection"
        static let launchAtLogin = "quickcopy.launchAtLogin"
        static let enabledActionIDs = "quickcopy.enabledActionIDs"
        static let didMigrateOpenLinkAction = "quickcopy.didMigrateOpenLinkAction"
        static let excludedAppBundleIDs = "quickcopy.excludedAppBundleIDs"
        static let excludedSiteHosts = "quickcopy.excludedSiteHosts"
        static let iconOnlyActions = "quickcopy.iconOnlyActions"
    }

    @Published var cornerRadius: Double {
        didSet { defaults.set(cornerRadius, forKey: Key.cornerRadius) }
    }

    /// 整个胶囊的缩放比例（0.8–1.5）。与圆角相互独立。
    @Published var capsuleScale: Double {
        didSet { defaults.set(capsuleScale, forKey: Key.capsuleScale) }
    }

    @Published var materialStyle: CapsuleMaterialStyle {
        didSet { defaults.set(materialStyle.rawValue, forKey: Key.material) }
    }

    @Published var animationDuration: Double {
        didSet { defaults.set(animationDuration, forKey: Key.animationDuration) }
    }

    @Published var popupOffsetX: Double {
        didSet { defaults.set(popupOffsetX, forKey: Key.popupOffsetX) }
    }

    @Published var popupOffsetY: Double {
        didSet { defaults.set(popupOffsetY, forKey: Key.popupOffsetY) }
    }

    /// 键盘 Shift+方向键、⌘A 等选字方式是否弹窗。默认 false。
    @Published var showOnKeyboardSelection: Bool {
        didSet { defaults.set(showOnKeyboardSelection, forKey: Key.showOnKeyboardSelection) }
    }

    /// 开机自启偏好。真正的 SMAppService 注册由 AppCoordinator 执行。
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    /// 启用动作的 id 列表，同时决定按钮顺序。
    @Published var enabledActionIDs: [String] {
        didSet { defaults.set(enabledActionIDs, forKey: Key.enabledActionIDs) }
    }

    /// 不弹出胶囊的 App bundle id 列表。
    @Published var excludedAppBundleIDs: [String] {
        didSet { defaults.set(excludedAppBundleIDs, forKey: Key.excludedAppBundleIDs) }
    }

    /// 不弹出胶囊的网站域名列表（已统一为小写、去掉 www. 和路径）。
    /// 匹配时会连同子域名一起排除。
    @Published var excludedSiteHosts: [String] {
        didSet { defaults.set(excludedSiteHosts, forKey: Key.excludedSiteHosts) }
    }

    /// 动作按钮是否只显示图标。默认 false（显示文字）。
    @Published var iconOnlyActions: Bool {
        didSet { defaults.set(iconOnlyActions, forKey: Key.iconOnlyActions) }
    }

    private let defaults: UserDefaults

    private static let defaultActionIDs = [
        "cut", "copy", "paste", "delete", "openLink", "search"
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let fallback = CapsuleConfiguration.default
        let storedCornerRadius = defaults.object(forKey: Key.cornerRadius) as? Double
            ?? Double(fallback.cornerRadius)
        let clampedCornerRadius = min(
            max(storedCornerRadius, 0),
            Double(CapsuleConfiguration.maximumCornerRadius)
        )
        cornerRadius = clampedCornerRadius
        let storedScale = defaults.object(forKey: Key.capsuleScale) as? Double
            ?? Double(fallback.scale)
        let clampedScale = min(
            max(storedScale, Double(CapsuleConfiguration.scaleRange.lowerBound)),
            Double(CapsuleConfiguration.scaleRange.upperBound)
        )
        capsuleScale = clampedScale
        materialStyle = Self.materialStyle(from: defaults.string(forKey: Key.material))
            ?? fallback.materialStyle
        animationDuration = defaults.object(forKey: Key.animationDuration) as? Double
            ?? fallback.animationDuration
        popupOffsetX = defaults.object(forKey: Key.popupOffsetX) as? Double
            ?? Double(fallback.popupOffset.width)
        popupOffsetY = defaults.object(forKey: Key.popupOffsetY) as? Double
            ?? Double(fallback.popupOffset.height)
        showOnKeyboardSelection = defaults.object(forKey: Key.showOnKeyboardSelection) as? Bool ?? false
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        var storedActionIDs = defaults.stringArray(forKey: Key.enabledActionIDs)
            ?? Self.defaultActionIDs
        if !defaults.bool(forKey: Key.didMigrateOpenLinkAction) {
            // 老版本没有“打开链接”动作。只迁移一次，之后用户主动关闭它不会被重新加回。
            if !storedActionIDs.isEmpty, !storedActionIDs.contains("openLink") {
                if let searchIndex = storedActionIDs.firstIndex(of: "search") {
                    storedActionIDs.insert("openLink", at: searchIndex)
                } else {
                    storedActionIDs.append("openLink")
                }
            }
            defaults.set(true, forKey: Key.didMigrateOpenLinkAction)
            defaults.set(storedActionIDs, forKey: Key.enabledActionIDs)
        }
        enabledActionIDs = storedActionIDs
        excludedAppBundleIDs = defaults.stringArray(forKey: Key.excludedAppBundleIDs) ?? []
        let storedSites = defaults.stringArray(forKey: Key.excludedSiteHosts) ?? []
        let normalizedSites = Self.normalizedSiteHosts(storedSites)
        excludedSiteHosts = normalizedSites
        if normalizedSites != storedSites {
            defaults.set(normalizedSites, forKey: Key.excludedSiteHosts)
        }
        iconOnlyActions = defaults.object(forKey: Key.iconOnlyActions) as? Bool
            ?? fallback.iconOnlyActions

        if clampedCornerRadius != storedCornerRadius {
            defaults.set(clampedCornerRadius, forKey: Key.cornerRadius)
        }
        if clampedScale != storedScale {
            defaults.set(clampedScale, forKey: Key.capsuleScale)
        }
    }

    /// UI 层使用的纯视觉配置快照。
    var capsuleConfiguration: CapsuleConfiguration {
        CapsuleConfiguration(
            cornerRadius: CGFloat(cornerRadius),
            scale: CGFloat(capsuleScale),
            materialStyle: materialStyle,
            animationDuration: animationDuration,
            popupOffset: CGSize(width: popupOffsetX, height: popupOffsetY),
            iconOnlyActions: iconOnlyActions
        )
    }

    func isActionEnabled(_ id: String) -> Bool {
        enabledActionIDs.contains(id)
    }

    func isAppExcluded(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return excludedAppBundleIDs.contains(bundleIdentifier)
    }

    /// 当前网页是否命中网站排除列表。匹配域名本身及其子域名。
    func isSiteExcluded(_ url: URL?) -> Bool {
        guard let host = Self.normalizedHost(url?.host) else { return false }
        return excludedSiteHosts.contains { pattern in
            host == pattern || host.hasSuffix("." + pattern)
        }
    }

    /// 添加网站排除项。支持 `example.com`、`https://example.com/path` 等写法。
    /// 返回 false 表示无法识别出域名。
    @discardableResult
    func addExcludedSite(_ raw: String) -> Bool {
        guard let candidate = Self.hostCandidate(from: raw),
              let url = URL(string: candidate),
              let host = Self.normalizedHost(url.host) else {
            return false
        }
        guard !excludedSiteHosts.contains(host) else { return true }
        excludedSiteHosts.append(host)
        return true
    }

    func removeExcludedSite(_ host: String) {
        excludedSiteHosts.removeAll { $0 == host }
    }

    private static func hostCandidate(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return trimmed
        }
        return "https://" + trimmed
    }

    private static func normalizedHost(_ rawHost: String?) -> String? {
        guard var host = rawHost?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty else {
            return nil
        }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        // 允许用户误粘贴带端口或末尾点号的地址。
        if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        if host.hasSuffix(".") {
            host.removeLast()
        }
        return host.isEmpty ? nil : host
    }

    private static func normalizedSiteHosts(_ rawValues: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in rawValues {
            guard let candidate = hostCandidate(from: raw),
                  let url = URL(string: candidate),
                  let host = normalizedHost(url.host),
                  !host.isEmpty,
                  seen.insert(host).inserted else {
                continue
            }
            result.append(host)
        }
        return result
    }

    func addExcludedApp(bundleID: String) {
        guard !bundleID.isEmpty, !excludedAppBundleIDs.contains(bundleID) else { return }
        excludedAppBundleIDs.append(bundleID)
    }

    func removeExcludedApp(bundleID: String) {
        excludedAppBundleIDs.removeAll { $0 == bundleID }
    }

    /// 勾选/取消动作。取消时从列表移除；重新勾选时追加到末尾。
    func setAction(_ id: String, enabled: Bool) {
        var ids = enabledActionIDs
        if enabled {
            if !ids.contains(id) {
                ids.append(id)
            }
        } else {
            ids.removeAll { $0 == id }
        }
        enabledActionIDs = ids
    }

    /// 把启用动作拖动到列表中的目标位置，顺序会同步到胶囊。
    func moveAction(_ id: String, to targetIndex: Int) {
        let original = enabledActionIDs
        guard let sourceIndex = original.firstIndex(of: id) else { return }

        var ids = original
        ids.remove(at: sourceIndex)
        let destination = min(max(targetIndex, 0), ids.count)
        ids.insert(id, at: destination)

        guard ids != original else { return }
        enabledActionIDs = ids
    }

    /// 恢复默认外观（设置页的“恢复默认”按钮可调用）。
    func resetAppearance() {
        let fallback = CapsuleConfiguration.default
        cornerRadius = Double(fallback.cornerRadius)
        capsuleScale = Double(fallback.scale)
        materialStyle = fallback.materialStyle
        animationDuration = fallback.animationDuration
        popupOffsetX = Double(fallback.popupOffset.width)
        popupOffsetY = Double(fallback.popupOffset.height)
        iconOnlyActions = fallback.iconOnlyActions
    }

    /// 读取已保存的外观样式，并把旧版四档磨砂迁移为统一的“磨砂”。
    private static func materialStyle(from rawValue: String?) -> CapsuleMaterialStyle? {
        guard let rawValue else { return nil }
        if let style = CapsuleMaterialStyle(rawValue: rawValue) {
            return style
        }
        switch rawValue {
        case "ultraThin", "thin", "thick":
            return .regular
        default:
            return nil
        }
    }
}