# QuickCopy

轻量的 macOS 划词工具（对标 PopClip 基础版）：选中文字后，在选区上方弹出原生胶囊，内置剪切、复制、粘贴、删除、打开链接和系统搜索。其中「打开链接」只在整段选区就是一个网页链接时出现。外观可选玻璃、磨砂、暗色或明亮，胶囊大小和圆角可调，动作顺序可在设置里按住拖动调整；还可以指定哪些应用和网站不弹出胶囊。

- Swift + SwiftUI，最低 macOS 13
- 仅本地运行，不联网、不上架 App Store
- 只使用公开的 Accessibility API，不拦截 ⌘C/⌘X/⌘V，不使用私有 API
- 胶囊为非激活面板：点击按钮不会把前台应用切成 QuickCopy

---

## 一、架构

```
              ┌───────────────────────────────┐
              │ AppDelegate / AppCoordinator  │  唯一装配点
              └───────┬───────────┬───────────┘
      ┌───────────────┤           ├────────────────┐
      ▼               ▼           ▼                ▼
AccessibilityService  ActionManager  CapsuleController  ConfigManager
  (只监听选区)        (注册/执行)      (窗口/位置/交互)     (全部可调项)
      │                   │               │                │
      │ SelectionContext  │ QuickAction   ▼                │
      └───────────────────┴──────► FloatingCapsuleView ◄────┘
                                     (纯 SwiftUI 展示)

MenuBarManager ── 状态栏图标 / 菜单（独立模块，与胶囊无耦合）
```

数据流：

- 鼠标拖选 → `AccessibilityService` 读取 `AXSelectedText` 与选区 bounds → 转成 Cocoa 坐标的 `SelectionContext`
- `AppCoordinator` → 按配置和选区过滤动作（剪切/粘贴/删除只在可编辑文本里出现；打开链接只在整段是网页链接时出现；排除的应用和网站直接不弹）→ `CapsuleController.show` → `FloatingCapsuleView` 渲染
- 点击按钮 → `CapsuleController` → `AppCoordinator` → `ActionManager.perform` → 具体动作（剪切/复制/粘贴/删除/打开链接/搜索）
- 结果回到 `CapsuleController.showFeedback`，按钮短暂变成绿色对勾后自动收起

`AccessibilityService` 不含任何 UI 代码，`FloatingCapsuleView` 不含任何业务逻辑，各层只通过 Coordinator 接线。

### 模块职责

| 文件 | 职责 |
| --- | --- |
| `App/QuickCopyApp.swift` | 进程入口，启动 AppKit 事件循环，`.accessory` 激活策略（无 Dock 图标） |
| `App/AppDelegate.swift` | 创建 Coordinator、设置窗口、菜单栏；负责启动与退出收尾 |
| `App/AppCoordinator.swift` | 依赖装配、选区到胶囊的流转、动作执行、权限与登录项副作用 |
| `Core/Protocols/QuickAction.swift` | 独立动作协议（含分组、只显图标、仅可编辑文本、按选区条件显示等属性）；注释中含新增动作的完整示例 |
| `Core/Actions/CutAction.swift` | 向来源 App 发送标准 ⌘X，由原 App 完成剪切；仅对可编辑选区展示 |
| `Core/Actions/CopyAction.swift` | 把选中文字写入 `NSPasteboard.general` |
| `Core/Actions/PasteAction.swift` | 向来源 App 发送标准 ⌘V；仅对可编辑选区展示 |
| `Core/Actions/DeleteAction.swift` | 向来源 App 发送标准 Delete（退格）键删除选区，不写入剪贴板；仅对可编辑选区展示 |
| `Core/Actions/OpenLinkAction.swift` | 把整段选区识别出的网页链接交给系统默认浏览器；只在 `isAvailable` 为真时显示 |
| `Core/Actions/SearchAction.swift` | 调用系统 Services 的 Safari 搜索服务，使用系统默认搜索引擎 |
| `Core/Services/KeyboardEventSender.swift` | 把 ⌘X/⌘V/Delete 发送给选区所属进程，不激活 QuickCopy |
| `Core/Services/ActionManager.swift` | 动作注册表、按配置顺序取启用动作、主线程回调 |
| `Core/Services/AccessibilityService.swift` | 权限、鼠标/键盘监听、AXObserver、读取并校验选区（含 Safari/WebKit 的 text marker 选区），并沿控件向上查找网页 URL |
| `Core/Services/ConfigManager.swift` | `@Published` 配置 + UserDefaults 持久化；应用排除、网站排除与域名归一化 |
| `Core/Services/MenuBarManager.swift` | `NSStatusItem`、启用/停用、设置、权限、退出菜单 |
| `Core/Services/LoginItemManager.swift` | `SMAppService.mainApp` 开机自启封装 |
| `Core/Models/SelectionContext.swift` | 选区文本、坐标、来源（鼠标/键盘）、是否可编辑、来源进程、来源网页 URL、签名 |
| `Core/Models/CapsuleConfiguration.swift` | 整体缩放、圆角、材质、动效时长、弹出偏移、动作按钮是否只显示图标 |
| `Core/Models/QuickActionResult.swift` | 动作执行结果（成功 / 失败信息） |
| `Core/Models/WebLinkDetector.swift` | 判断整段选区是否为一个 http/https 网页链接（`NSDataDetector` + 严格边界校验） |
| `Windowing/FloatingPanel.swift` | 无边框、非激活、置顶、透明背景的 `NSPanel` |
| `Windowing/CapsuleController.swift` | 定位、屏幕夹取、翻转到下方、外部点击/ESC/切换 App 收起、对勾反馈 |
| `UI/FloatingCapsuleView.swift` | 胶囊按钮行，所有样式值来自 `CapsuleConfiguration` |
| `UI/SettingsView.swift` | 侧栏式设置页：外观、行为、动作、应用与网站、隐私与权限五个页面，外观页含实时胶囊预览 |
| `UI/SettingsChrome.swift` | 设置页页面模型、侧栏、分组卡片、材质选择、开关/滑块/偏移控件和隐私条目等共享组件 |
| `UI/SettingsWindowController.swift` | 设置窗口宿主：900×660、最小 800×560、隐藏标题、侧栏延伸到红绿灯下方 |
| `Resources/AppIcon.icns` | 应用图标（由 `tools/make_icon.swift` 生成） |
| `Resources/Info.plist` | `LSUIElement = true`，bundle id `com.jeff.quickcopy`，图标 `AppIcon` |
| `Resources/QuickCopy.entitlements` | 空权限；不使用 App Sandbox（本地分发） |

---

## 二、构建与运行

### 方式 A：命令行（推荐，重建不丢权限）

```bash
cd QuickCopy
./build.sh
open build/QuickCopy.app
```

首次运行会在 `~/Library/Application Support/QuickCopy/signing/` 创建固定的本机自签证书 `QuickCopy Local Signing`（私钥在独立钥匙串，不影响登录钥匙串），之后每次构建都用它签名。

签名身份固定后，App 的 designated requirement 是：

```
identifier "com.jeff.quickcopy" and certificate root = H"..."
```

重建只会改变 cdhash，不会改变这条 requirement，所以辅助功能授权对后续构建继续有效。

> 从旧的 ad-hoc 签名切换过来时，身份确实变了，需要最后手动授权一次；之后重编不用再来回勾选。ad-hoc 的 cdhash 每次都会变，才会导致反复授权。

证书只在缺失时创建，也可以单独执行：

```bash
./tools/make_signing_cert.sh
```

### 方式 B：Xcode

1. `open QuickCopy.xcodeproj`
2. Target `QuickCopy` → Signing & Capabilities：不要开启 App Sandbox。
3. 选择 `My Mac`，Run。

注意：Xcode 默认的 “Sign to Run Locally” 是 ad-hoc 签名，会重新触发辅助功能授权。需要保留授权时请用 `./build.sh`，或在 Xcode 中手动改用同一张 `QuickCopy Local Signing` 证书。

工程由命令行生成，已通过 `plutil -lint` 校验；本机只有 Command Line Tools 的环境无法执行 `xcodebuild`，请以 Xcode 实际编译结果为准。

### 应用图标

图标由代码绘制，不依赖外部设计文件：

```bash
swift tools/make_icon.swift
```

会生成 `QuickCopy/Resources/AppIcon.icns` 和 1024px 预览 `build/AppIcon-1024.png`。设计是蓝紫渐变圆角方形 + 平铺在蓝底上的大号复制图形：后页半透明并露出淡淡的文字线，前页有蓝紫渐变文字线、底部内阴影和右下折角，底色带斜向玻璃高光和内侧高光圈。

---

## 三、辅助功能权限

QuickCopy 依赖 Accessibility API 读取选区：

1. 首次启动会请求一次授权（之后不再主动弹窗）。
2. 前往 **系统设置 → 隐私与安全性 → 辅助功能**，勾选 QuickCopy。
3. 也可以打开菜单栏图标的 **设置…**，在左侧选择 **隐私与权限** 查看授权状态；或直接点菜单里的 **辅助功能权限…**。

macOS 26/27 的第三方辅助功能授权界面可能显示为“系统与应用保护覆盖”：需要给 QuickCopy 授予完整覆盖，而不是只勾选单个 App。只勾选 scoped 时 `AXIsProcessTrusted()` 可能返回真，但读取控件会拿不到内容。

说明与边界：

- 只读取当前焦点控件的 `AXSelectedText`、`AXSelectedTextRange`、`AXBoundsForRange` 等公开属性，用于判断“选了什么、选区在哪”。
- 不监听输入内容、不记录键盘、不访问网络、不保存选中的文字（复制后只存在于系统剪贴板）。
- 邮箱/密码框等 `AXSecureTextField` 会被主动跳过。
- 全局事件监听（鼠标、ESC）同样依赖该授权；未授权时胶囊不会出现。

---

## 四、交互与实现要点

- 鼠标拖选过程中不展示；松开鼠标/触控板后**立即**读取选区并瞬时显示（无淡入、无位移）。仅单击或不足 3pt 的抖动不触发。
- 为消除固定等待：优先复用 `AXObserver` 已缓存的焦点元素，省掉每次重新查询焦点的 IPC；若目标 App 还没提交新选区，才做 8ms / 20ms 两次极短重试。
- 启动时先在不可见的面板里完成一次按钮视图排版与 Liquid Glass 初始化，避免第一次划词时把 SwiftUI 首次渲染耗时叠加进弹出延迟。
- 拖选期间会忽略 `AXSelectedTextChanged` 通知，松开后由鼠标抬起事件统一触发一次，避免“刚划上就弹出”。
- 默认不响应键盘 Shift+方向键 / ⌘A 选字；设置页可开启。开启后同样等按键松开再读取。
- Safari 等 WebKit 应用不提供 `AXSelectedText`，改用 `AXSelectedTextMarkerRange` + `AXStringForTextMarkerRange` / `AXBoundsForTextMarkerRange` 读取选区；其它应用仍走标准 `AXSelectedText`。
- 部分 Electron/Chromium 控件（如 Qoder）能提供 `AXSelectedText`，但 `AXBoundsForRange` 返回空矩形；此时同样回退到 `AXSelectedTextMarkerRange` 的选区矩形，避免胶囊退回鼠标点并挡住文字。
- 配置里的“动画时长”只控制消失和位置变化。
- 胶囊水平居中于鼠标松开位置，垂直方向按**选区高亮的上边界**定位：以选区矩形（按行数估算半个行高、最多 9pt 向外扩展）作为蓝色阴影的近似范围，再整体放在它的上方，尽量缩短手移到按钮的距离，多行选区也不会盖住选中文字。可通过设置里的 X/Y 偏移微调；上方空间不足时翻到整个选区下方，并夹取在当前屏幕可见区域内。
- 公开的 Accessibility API 不暴露系统绘制的高亮矩形，只能拿到文字范围；Safari/Chromium 的 text marker 矩形又比高亮更贴字。因此用“行数 × 半个行高”向外扩一点来贴近阴影边界，而不是精确读取高亮。实测 Safari 中胶囊底边与蓝色高亮之间保留约 5pt 空隙。
- 部分应用不提供选中范围的精确矩形时，鼠标选区退回鼠标抬起位置定位，避免用整个输入框的 frame 把胶囊推到很远的地方。
- 面板为 `.borderless + .nonactivatingPanel`，层级 `.statusBar`，可跨 Space 和全屏显示；点击按钮不会激活 QuickCopy，源应用保持前台。面板不成为 key window，按键焦点始终留在原 App，剪切/粘贴/删除发送的按键才会落到原来的编辑区域。
- macOS 26 及以上使用系统原生 Liquid Glass（设置里名为「玻璃」，`.glassEffect`）；选择磨砂时使用系统标准材质；选择“暗色”时使用近乎不透明的深色底、白色图标/文字和浅色分隔线；选择“明亮”时使用近白底、黑色图标/文字和深色分隔线。暗色和明亮都固定为对应明暗，不随系统外观变化。
- `CapsuleHostingView` 重写了 `acceptsFirstMouse`，从其他 App 直接点按钮时第一次点击就生效，不需要“先点一下激活”。
- 点击胶囊外部、按 ESC、选区消失、切换到其他 App、动作完成都会收起；动作成功显示绿色对勾约 0.8 秒。
- 同一选区在关闭后 0.6 秒内不会立刻重新弹出（避免 AX 通知重复触发导致闪烁）。
- 设置窗口采用侧栏式导航：外观、行为、动作、应用与网站、隐私与权限。窗口默认 900×660、最小 800×560，隐藏标题栏文字并用 `fullSizeContentView` 让侧栏背景延伸到红绿灯下方；未授权时首次打开会直接落在“隐私与权限”。
- 外观页顶部复用真正的 `FloatingCapsuleView` 做实时预览：切换材质、调整大小/圆角、只显示图标或调整动作顺序都会立即反映。材质使用四块色板卡片而不是下拉框，偏移量使用紧凑的 − / + 控件。圆角滑块上限为 18pt（超过后外观不再变化），只显示滑动条、不显示像素数值。页面切换会把滚动位置重置到顶部。
- 「胶囊大小」滑块按 80%–150% 整体缩放胶囊：字号、内边距、图标、分隔线与圆角同比变化，预览和下一次弹出立即生效，窗口尺寸随内容自适应（实测双按钮胶囊 100% 时 87×51，150% 时 119×67）。
- 设置页的“不启用的应用”按 bundle id 排除：在这些应用里划词不会弹出胶囊，其它应用不受影响。
- 设置页的“不启用的网站”按域名排除：可输入 `example.com` 或完整网址（如 `https://news.ycombinator.com/item?id=1`），保存时只取主机名并统一小写、去掉 `www.`、端口和路径；匹配该域名及其所有子域名。网页 URL 从 `AXURL` / `AXDocument` 读取，适用于 Safari、Chrome、Edge 和多数内嵌网页；不记录浏览历史或选中的文字。个别不暴露网页地址的应用无法按网站排除。
- 网站排除在选区处理时用当前网页 host 与列表做本地比较；增删列表会立即让已显示的胶囊收起，不需要重启。排除粒度是整站域名，不支持只排除某个路径或单页。
- 剪切、复制、粘贴、删除按 PopClip 的方式分组；「打开链接」和「搜索」属于同一组额外入口，与编辑动作之间用一条细线隔开。搜索本身只显示放大镜图标，悬停显示“搜索”。
- 设置里的动作卡片左侧有三条横线拖动手柄，按住一行上下拖动即可调整启用动作的顺序。动作行只显示中文名称和图标，不再显示 `cut`/`copy` 等英文 id。拖动时整行（含图标、文字和右侧开关）浮起跟随鼠标，其余行实时让位，不会只剩文字跟着指针；顺序直接对应胶囊里的按钮顺序。关闭的动作会排在列表末尾，重新开启后追加到末尾。顺序写入 `enabledActionIDs`，重启后保留。
- 设置里的“动作按钮只显示图标”可让剪切/复制/粘贴/删除也隐藏文字，只留图标；胶囊会随之变窄，悬停按钮仍会显示动作名称。搜索本来就只显示图标，不受影响。
- 剪切/粘贴/删除只在可编辑选区出现：网页正文、预览类只读文字不会看到这三个按钮。判断依据是 `AXEditable` 和 `AXSelectedText` 是否可写，而不是控件类型。
- 剪切/粘贴不直接改文本：点击后把标准 ⌘X/⌘V 发送给选区所属进程，由原 App 自己完成编辑，保持富文本、图片、文件等原生行为。删除发送标准退格键，同样由原 App 自己删除选区，不读写剪贴板。
- 搜索调用 macOS Services 中 Safari 的“Search With %WebSearchProvider@”服务，与文本右键菜单里的搜索一致，使用系统当前的默认搜索引擎；查询词放在独立剪贴板里，不覆盖用户剪贴板。
- 「打开链接」只在整段选区（去掉首尾空白后）本身就是一个网页链接时出现，包括 `https://…`、`www.…` 和裸域名；允许链接两侧带引号、括号或句号等标点。包含空格、句子中间夹链接、邮箱、文件名（如 `README.md`）、`mailto:`/`file:` 等非 http(s) 内容都不会出现该按钮。识别用 `NSDataDetector`，不访问网络、不抓取页面；点击后只把 URL 交给 `NSWorkspace`，由系统默认浏览器打开。
- 旧版本配置首次启动时会自动把 `openLink` 插入到 `search` 前面，只迁移一次；之后在设置里手动关闭它不会被重新加回。设置页顶部的实时预览使用普通示例文字，因此不会显示这个上下文动作。
- 不注册任何 ⌘C/⌘X/⌘V 快捷键，也不拦截它们；只有点击胶囊里的剪切/复制时才会改变系统剪贴板，删除不会写入剪贴板。

### 配置项（均持久化）

| 设置 | 默认值 | 说明 |
| --- | --- | --- |
| 胶囊大小 | 100% | 整体缩放 80%–150%，字号、内边距、图标、分隔线与圆角同比变化 |
| 圆角 | 18 | 胶囊圆角，可调 0–18pt；设置页只显示滑动条，超过 18pt 后外观不再变化 |
| 材质 | 玻璃 | macOS 26+ 用原生 Liquid Glass；旧系统回退磨砂；也可手动选磨砂（系统标准材质）、暗色（固定深色底白字）或明亮（固定白底黑字） |
| 动效时长 | 0.12s | 只控制消失和位置变化，出现为瞬时 |
| 弹出偏移 X / Y | 0 / 8 | 水平相对鼠标松开位置，垂直相对选区上边缘；键盘选区相对文段中心 |
| 动作按钮只显示图标 | 关 | 开启后剪切/复制/粘贴/删除隐藏文字，仅显示图标；悬停仍显示名称 |
| 键盘选字弹窗 | 关 | Shift+方向键、⌘A 等 |
| 开机自启 | 关 | `SMAppService.mainApp` |
| 启用动作 | `["cut", "copy", "paste", "delete", "openLink", "search"]` | 同时决定按钮顺序，可在设置里拖动调整；剪切/粘贴/删除在只读选区自动隐藏，打开链接只在整段是网页链接时出现 |
| 不启用的应用 | 空 | 按 bundle id 排除，划词不弹胶囊 |
| 不启用的网站 | 空 | 按域名（含子域名）排除；菜单里可输入域名或完整网址，只保存主机名 |

设置页修改外观会实时作用于已显示或下一次显示的胶囊。

---

## 五、新增自定义动作（无需改动胶囊 UI）

动作协议在 `Core/Protocols/QuickAction.swift`，完整示例也写在文件注释里。最小步骤：

```swift
import AppKit

final class TranslateAction: QuickAction {
    let id = "translate"
    let title = "翻译"
    let systemImageName = "character.book.closed"

    func perform(on context: SelectionContext,
                 completion: @escaping (QuickActionResult) -> Void) {
        // 这里放你自己的逻辑；保持回调在主线程调用。
        completion(.success)
    }
}
```

然后在 `AppCoordinator.registerActions()` 中注册，并把 id 加进启用列表：

```swift
actionManager.register(TranslateAction())
config.setAction("translate", enabled: true)   // 或在设置页勾选
```

不需要修改 `FloatingCapsuleView`、`CapsuleController` 或 `ActionManager`：胶囊会按 `enabledActionIDs` 的顺序自动渲染新按钮，点击后由 `ActionManager` 统一执行并回调成功/失败反馈。可选展示属性都有默认值：`visualGroup`（同组不加分隔线）、`showsTitle`（是否显示文字，会与设置里的全局“只显示图标”叠加）、`requiresEditableText`（仅可编辑选区显示）、`isAvailable(for:)`（按选区内容决定是否显示，默认全部显示）。上下文动作可以参考 `OpenLinkAction` 的写法。

如果希望新动作默认启用，可把 `ConfigManager` 中 `enabledActionIDs` 的兜底值（当前为 `["cut", "copy", "paste", "delete", "openLink", "search"]`）改成包含 `"translate"` 的列表；已有安装需要自行加一次迁移，或直接在设置页勾选。

---

## 六、测试清单

基础流程（需先授予辅助功能权限）：

- [ ] 菜单栏出现图标，启动无 Dock 图标、无主窗口
- [ ] Finder / 系统设置里显示新的 QuickCopy 图标（蓝紫渐变 + 大号复制图形）
- [ ] 在 Safari / 备忘录 / 文本编辑中鼠标拖选一段文字，拖选**过程中不出现**胶囊，松开后胶囊**瞬时**出现在整个选区上边缘上方
- [ ] 连续划选不同文字时，从松手到看见胶囊应接近即时（正常在 1~2 帧内），不应有固定的“等一下”感
- [ ] 按 ESC 或点击外部关闭后，重新拖选同一段文字，胶囊会再次出现（不需要换一段文字）
- [ ] 跨多行选择、且在最后一行松开时，胶囊仍位于整个选段上方，不覆盖任何选中文字
- [ ] 胶囊底边停在蓝色高亮的上方，而不是贴着文字字形；Safari 中两者之间应留有可见空隙（实测约 5pt）
- [ ] 在 Qoder 等只提供 text marker 矩形的 Electron 应用中，多行选区同样能定位到整段上方
- [ ] Safari 中划词能正常弹出（WebKit 走 `AXSelectedTextMarkerRange`），点击“复制”得到与选中文字一致的内容
- [ ] 网页正文等只读选区只显示「复制」和「搜索」，不显示剪切/粘贴/删除；若整段选中内容本身就是网页链接，会多一个「打开链接」
- [ ] 选中完整网页链接（`https://example.com`、`www.apple.com` 或裸域名 `apple.com`）时出现「打开链接」，点击后用系统默认浏览器打开对应页面
- [ ] 选区只是句子的一部分、包含空格、或为邮箱 / 文件名 / `mailto:` 等非 http(s) 内容时，不出现「打开链接」
- [ ] 带首尾标点的链接（如 `(https://example.com)。`）仍能识别并打开正确的 URL
- [ ] 在 Safari 输入框 / 备忘录 / 文本编辑里选中文字，五个按钮齐全；点击“剪切”，文字消失且剪贴板内容一致
- [ ] 在可编辑区域选中文字后点击“粘贴”，选区被剪贴板内容替换，剪贴板本身保持不变
- [ ] 在可编辑区域选中文字后点击“删除”，选区被删除，剪贴板内容保持不变
- [ ] 剪贴板为空时点击“粘贴”，按钮显示红色叉号提示
- [ ] 点击“搜索”，用系统默认搜索引擎在 Safari 打开结果页，查询词与选中文字一致
- [ ] 胶囊在 macOS 26+ 呈玻璃（Liquid Glass）效果，能透出下方内容
- [ ] 设置里的材质卡片只保留「玻璃 / 磨砂 / 暗色 / 明亮」四项；旧配置里的超薄/薄/厚磨砂会自动落到“磨砂”
- [ ] 切到“暗色”后胶囊为深色底、白色图标/文字和浅色分隔线；切到“明亮”后为近白底、黑色图标/文字和深色分隔线；两者都不随系统亮/暗模式变化
- [ ] 点击“复制”，剪贴板内容与选中文字完全一致，按钮短暂显示绿色对勾后收起
- [ ] 点击胶囊外部，胶囊立即收起，原应用不受影响
- [ ] 按 ESC，胶囊收起
- [ ] 取消选中文字（点空白处），胶囊收起
- [ ] 切换到其他 App，胶囊收起
- [ ] 单击不弹胶囊；双击选词、三击选段在松开后正常弹出
- [ ] 按住 Shift+方向键选字，默认不弹；在设置中打开“键盘选字”后能弹
- [ ] 未选中文字时拖拽，不弹胶囊
- [ ] 在密码框/安全输入框中选中文字，不弹胶囊
- [ ] ⌘C/⌘X/⌘V 行为与系统一致，不被 QuickCopy 拦截

设置与配置：

- [ ] 打开设置后显示左侧栏（外观 / 行为 / 动作 / 应用与网站 / 隐私与权限），窗口默认 900×660；红绿灯下方侧栏背景连续，不与内容区割裂
- [ ] 外观页顶部的实时预览会随材质、大小、圆角、只显示图标、动作顺序立即变化；材质四块色板均可选中并有勾选状态，磨砂色板四角没有黑色漏底；圆角滑块只显示滑动条、没有像素数值
- [ ] 拖动「胶囊大小」滑块，预览和下一次弹出的胶囊同步变大/变小，图标、内边距和圆角一起缩放；重启后保留
- [ ] 未授权辅助功能时打开设置，默认落在“隐私与权限”，侧栏底部状态卡为橙色并可点击跳转
- [ ] 在任意页面滚动后切换到另一页，新页面从顶部开始显示
- [ ] 把窗口缩到最小 800×560，材质色板、说明文字和权限卡片仍完整可用，内容可滚动
- [ ] “应用与网站”页空状态显示“尚未添加应用”，添加后可看到应用图标/名称/bundle id，并能移除
- [ ] 网站空状态显示“尚未添加网站”；点击“添加网站…”，输入 `example.com` 或完整网址都能保存为纯域名，列表中显示“该域名及其子域名”
- [ ] 已排除的网站在 Safari/Chrome 中划词不弹胶囊，其子域名同样不弹；其它网站正常
- [ ] 从网站列表移除后，该网站恢复弹胶囊；增删列表时已显示的胶囊立即收起
- [ ] 修改大小/圆角/材质/动效/偏移后立即生效，重启后保留
- [ ] 开启“动作按钮只显示图标”后，可编辑选区的五个按钮只显示图标并变窄；切换暗色/明亮后图标仍清晰；关闭后恢复文字标签，重启后设置保留
- [ ] 按住动作卡片的一行上下拖动，拖动时整行（含右侧开关）浮起、其余行实时让位（例如把“复制”拖到第一）；胶囊按钮顺序同步变化，重启后顺序保留
- [ ] 关闭一个动作后它排到列表末尾；重新开启后追加到启用列表末尾
- [ ] 关闭「打开链接」后，选中网页链接也不再显示该按钮；重新开启后追加到启用列表末尾
- [ ] 从旧版本升级（没有 `openLink` 的配置）首次启动后，`openLink` 自动插在 `search` 前面；之后手动关闭不会被重新加回
- [ ] 外观页的实时预览使用普通示例文字，不显示上下文相关的「打开链接」
- [ ] 只读选区开启“只显示图标”时，仅显示复制和搜索两个图标
- [ ] 关闭“启用划词”后不再弹胶囊，菜单栏图标状态同步
- [ ] 关闭“复制”动作后，剪切/粘贴/删除/搜索仍可用；全部动作都关闭后划词不弹胶囊
- [ ] 把一个 App 加入“不启用的应用”，在该 App 内划词不弹胶囊，其它 App 正常
- [ ] 从排除列表移除后，该 App 恢复弹胶囊
- [ ] “打开系统设置”能跳到辅助功能页面；“重新检查”能刷新授权状态
- [ ] 开机自启开关在 `/Applications` 下的正式签名版本中生效

权限与签名：

- [ ] 首次用 `build.sh` 的证书构建后授权一次
- [ ] 再次 `./build.sh` 覆盖安装，辅助功能授权仍然有效（cdhash 变了但签名身份不变）

边界场景：

- [ ] 选区贴近屏幕顶部时，胶囊翻到选区下方
- [ ] 选区贴近左右边缘时，胶囊不被裁出屏幕
- [ ] 多显示器之间拖选，胶囊出现在当前屏幕内
- [ ] 快速连续选择不同文字，胶囊跟随且不闪烁

---

## 七、已知限制

- **固定签名与 TCC**：已经从 ad-hoc 切到 `QuickCopy Local Signing`，切换这一次需要重新授权；之后用 `./build.sh` 重编不需要。若删除 `~/Library/Application Support/QuickCopy/signing/` 下的证书，签名身份会变化，需要重新授权。
- **Xcode 的 ad-hoc 签名**：Xcode 里选择 “Sign to Run Locally” 会绕过固定证书，重新触发授权；日常运行建议用 `./build.sh`。
- **剪切/粘贴/删除依赖原 App**：动作发送标准 ⌘X/⌘V/Delete，由来源 App 自己执行；不支持编辑的应用或控件不会生效。可编辑性通过 AX 属性判断，个别自绘文本控件可能判断不准。粘贴和删除只能确认按键已投递，无法确认目标 App 一定接受。
- **搜索依赖 Safari 服务**：调用 Services 中的 Safari 搜索服务，使用系统默认搜索引擎；如果该服务不可用，会退回默认浏览器 + 百度。QuickCopy 本身不联网。
- **不是所有应用都暴露选区**：Safari 这类 WebKit 应用通过 `AXSelectedTextMarkerRange` 读取，已经支持；但部分 Electron / 自绘文本控件、某些终端既不提供 `AXSelectedText` 也不提供 text marker，此时无法读取，属于 Accessibility API 的客观边界。
- **高亮边界只能近似**：公开 AX API 没有“蓝色高亮矩形”这个属性，只能拿到文字范围；text marker 返回的矩形又比高亮更贴字。因此按行数把矩形上下各扩半个行高（最多 9pt）来逼近阴影边界，极端字号、行距或自定义高亮样式下仍可能有 1–2pt 偏差。
- **网站排除依赖网页 URL**：只有应用把当前网址暴露为 `AXURL` 或 `AXDocument` 时才能匹配，Safari、Chrome、Edge 和多数内嵌网页可用；个别不暴露地址的 App 或自绘浏览器无法按网站排除。匹配粒度为域名及子域名，不区分路径，也不保存浏览历史。
- **键盘选字判断是模式匹配**：通过 Shift+方向键 / Home / End / PageUp / PageDown / ⌘A 等按键组合触发，特殊输入法或自定义快捷键可能不覆盖。
- **开发版开机自启**：`SMAppService` 对未放入 `/Applications` 的构建可能注册失败，应用会回滚开关并给出提示。
- **阴影留白**：窗口四周有 10pt 透明阴影边距，视觉胶囊之外的透明区域不响应点击（属预期）。
- **“玻璃”的系统要求**：原生 Liquid Glass 只在 macOS 26+ 生效，旧系统会自动退回磨砂；“暗色”和“明亮”是固定纯色底，不依赖系统玻璃，也不随亮/暗模式变化。
- **未做公证分发**：本项目仅本地运行，不包含 App Store 配置与 notarization 流程。
- **验证范围**：Liquid Glass 渲染、居中定位、非激活点击、复制、对勾反馈已用独立 AppKit 测试壳验证；Safari 的“松开后弹窗、光标上方定位、点击复制”已用合成拖选实际验证（走 `AXSelectedTextMarkerRange` 路径）。剪切/粘贴已在 Safari 可编辑输入框中实际验证（文字被移除 / 被替换，剪贴板符合预期），只读网页正文会自动隐藏这两个按钮；搜索已实际打开系统默认搜索引擎的结果页。“动作按钮只显示图标”已在 Safari 可编辑输入框和只读正文中实际验证：可编辑下的动作与只读下的两个动作都只显示图标且胶囊同步变窄。新增的“删除”已在 Safari 可编辑输入框中实测：已选文字被移除、剪贴板保持不变，只读正文不显示删除；“暗色”已分别在只读两个图标、可编辑五个图标和文字标签三种状态下截图检查，深色底、白色图标/文字、浅色分隔线与宽度均正常；“明亮”已在可编辑图标模式和文字标签模式截图检查，白底黑字与分隔线清晰。设置页的材质色板已实际打开确认只有四项，第一项显示为「玻璃」；动作卡片的整行拖动也已实测：左侧三条横线手柄正常显示，按住“复制”行向下拖动时，完整一行（含右侧开关）浮起并跟随指针，其余行实时让位，松手后列表和 `enabledActionIDs` 变为 `cut, paste, delete, copy, search`，配置持久化正确。设置窗口改版后已用 2x 截图检查五个侧栏页面、900×660 与最小 800×560 布局、材质/只显示图标切换时的实时预览、页面切换回到顶部，以及在新布局中重新拖动动作行；测试后偏好已恢复为玻璃、只显示图标和默认动作顺序。多行选区定位也已实测：在 Safari 第三行松开、以及在 Qoder 两行消息中松开时，胶囊都位于整个选段上方而不是松开点上方；Qoder 的选区矩形通过 text marker 回退获取。延迟用 CGEvent 合成拖选 + 1ms 轮询 `CGWindowList` 实测（轮询与窗口合成本身也有开销）：Qoder 从松手到检测到胶囊约 25~27ms，Safari 约 33~46ms；应用内从松手到调用 `orderFront` 的热路径约 3~9ms（冷启动首次约 25ms），选区读取约 1~3ms。修改前是固定 10ms 等待再重新查询焦点，整段读取约 20~40ms。「打开链接」已用 26 个样例单测识别规则（完整 URL、`www`/裸域名、带标点、句子中夹链接、邮箱、文件名、非 http(s) 等），并在 TextEdit 中实测：选中整段 `https://example.com` 时胶囊出现六个按钮，点击“打开链接”后 Safari 打开该地址；选中普通中文句子时只有五个按钮，没有“打开链接”。图标已生成并检查 1024/128px 效果。高亮定位与胶囊大小已实测：Safari 中胶囊底边与蓝色选区顶部之间约 5.5pt，不覆盖高亮；双按钮胶囊在 100% 时窗口 87×51、150% 时 119×67，字号/内边距/图标/圆角同步缩放。网站排除已通过设置界面完整走通：在“应用与网站”页添加 `https://news.ycombinator.com/item?id=1` 后只保存 `news.ycombinator.com`（测试中发现并修复了把 `https` 误存为域名的问题），列表显示域名与“该域名及其子域名”，移除按钮可立即删除；排除 `example.com` 后在该页划词不出现任何胶囊窗口，未排除的本地页面仍正常弹出。测试后已恢复默认大小与空网站列表，并关闭测试标签页与本地服务器。其它应用和排除列表仍建议按上面的清单手动过一遍。本机没有完整 Xcode，Xcode 工程未经过 `xcodebuild` 实际编译，而是用同一批源文件通过 `build.sh` 编译验证。