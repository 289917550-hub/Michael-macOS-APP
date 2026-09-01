import AppKit
import CoreGraphics
import Carbon.HIToolbox
import ServiceManagement

// MARK: - 常量

let kToggleKeyCode: UInt32 = UInt32(kVK_ANSI_D)          // D = Display
let kToggleFlags: NSEvent.ModifierFlags = [.command, .option, .control]

/// kCGDisplay* 系列在新版 SDK 里已无 Swift 命名，按 CGDisplayConfiguration.h 的位定义自己声明：
/// add = 1<<4, remove = 1<<5, enabled = 1<<8, disabled = 1<<9
private enum DisplayChange: UInt32 {
    case add      = 0x0010
    case remove   = 0x0020
    case enabled  = 0x0100
    case disabled = 0x0200
}

private var appDelegateRef: AppDelegate?

// MARK: - 命令行模式（便于脚本调用与自检）

enum CLIEntry {

    static let usage = """
    DisplayToggle 1.0 — 开盖状态下开关 MacBook 内置屏

      --list              列出所有显示器（含已关闭的）与后端状态
      --off               关闭内置屏
      --on                恢复内置屏
      --display <id> on|off   按 id 开关任意显示器（id 用 --list 查）
      --selftest          关 3 秒再自动恢复（需要至少 2 块屏正在输出）
      --diagnose          打印完整诊断信息（遇到问题请先跑这个，把输出贴给开发者）
      --help              显示本帮助

    不带参数运行则启动菜单栏常驻程序。
    """

    static func handle(_ args: [String]) -> Bool {
        switch args[0] {
        case "--list", "-l":
            list()
            return true
        case "--off":
            print("关闭内置屏 → " + DisplayController.setBuiltIn(on: false).message)
            return true
        case "--on":
            print("恢复内置屏 → " + DisplayController.setBuiltIn(on: true).message)
            return true
        case "--display":
            display(args)
            return true
        case "--selftest":
            selfTest()
            return true
        case "--diagnose":
            diagnose()
            return true
        case "--help", "-h":
            print(usage)
            return true
        default:
            return false
        }
    }

    private static func diagnose() {
        print("============================================================")
        print(" DisplayToggle 诊断报告（请把下面所有输出完整贴给开发者）")
        print("============================================================")
        print()
        DisplayManager.diagnosePrint()
        print()
        NativeSPI.diagnosePrint()
        print()
        print("💡 [偏好设置当前值]")
        print("    backend = \(Preferences.backend) （\(Backend(rawValue: Preferences.backend)?.title ?? "未知")）")
        print("    autoDisableBuiltIn = \(Preferences.autoDisableBuiltIn) （接上外接屏时自动关内屏）")
        print("    autoRestoreBuiltIn = \(Preferences.autoRestoreBuiltIn) （外屏拔掉时自动恢复内屏）")
        print("    launchAtLogin = \(Preferences.launchAtLogin)")
        print("    betterDisplayNamePattern = \(Preferences.betterDisplayNamePattern)")
        print()
        // 再把 --list 的结果也输出，方便对照
        print("💡 [known() 枚举结果]")
        let all = DisplayManager.known()
        print("    已知 \(all.count) 块 / 正在输出 \(DisplayManager.activeCount()) 块")
        for d in all { print("      id=\(d.id)  \(d.label)") }
        if let b = DisplayManager.builtIn() {
            print("    ✅ DisplayManager.builtIn() → id=\(b.id) active=\(b.isActive)")
        } else {
            print("    ❌ DisplayManager.builtIn() → 没找到！（通常是扫描范围或 flag 判断的问题）")
        }
        print()
        print("============================================================")
        print(" 诊断完成。请把上面的全部输出贴给开发者，不要只截取部分。")
        print("============================================================")
    }

    private static func list() {
        let all = DisplayManager.known()
        print("已知 \(all.count) 块 / 正在输出 \(DisplayManager.activeCount()) 块")
        for d in all { print("  id=\(d.id)  \(d.label)") }
        print("后端          : \(Backend(rawValue: Preferences.backend)?.title ?? "自动")")
        print("系统原生 API  : \(NativeSPI.isAvailable ? "可用" : "不可用")")
        print("BetterDisplay : \(CLI.locate(["betterdisplaycli"]) ?? CLI.locateAppBinary("BetterDisplay") ?? "未安装")")
        print("Lunar         : \(CLI.locate(["lunar"]) ?? "未安装")")
    }

    private static func display(_ args: [String]) {
        guard args.count >= 3,
              let raw = UInt32(args[1]),
              (args[2] == "on" || args[2] == "off") else {
            print("用法: DisplayToggle --display <id> on|off")
            print("      先用 --list 查看各显示器的 id")
            return
        }
        let id = CGDirectDisplayID(raw)
        let wantOn = args[2] == "on"
        let name = DisplayManager.known().first(where: { $0.id == id })?.name
        let verb = wantOn ? "恢复" : "关闭"
        print("\(verb)显示器 \(id) → " + DisplayController.setDisplay(id: id, on: wantOn, fallbackName: name).message)
    }

    private static func selfTest() {
        print("自检：关闭内置屏 3 秒后自动恢复")
        guard DisplayManager.activeCount() >= 2 else {
            print("中止：正在输出的显示器不足 2 块，测试会让你彻底没有画面。")
            print("      请先接上外接显示器再运行。")
            return
        }
        let off = DisplayController.setBuiltIn(on: false)
        print("  关闭 → \(off.message)")
        guard off.isOK else { return }

        Thread.sleep(forTimeInterval: 3)

        let on = DisplayController.setBuiltIn(on: true)
        print("  恢复 → \(on.message)")
        if !on.isOK {
            print("  !! 恢复失败：合上再打开笔记本盖子，即可强制恢复内置屏。")
        }
    }
}

// MARK: - 开机自启

enum LaunchAtLogin {
    static func setEnabled(_ on: Bool) {
        guard #available(macOS 13.0, *) else { return }
        if on { try? SMAppService.mainApp.register() }
        else  { try? SMAppService.mainApp.unregister() }
    }

    static var isEnabled: Bool {
        get {
            guard #available(macOS 13.0, *) else { return false }
            return SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var ignoreChangeUntil = Date.distantPast
    private var pendingAuto: DispatchWorkItem?
    private var pollTimer: DispatchSourceTimer?

    // MARK: - 幻影屏/枚举切换检测

    /// 手动关内屏成功那一刻，NSScreen 层面存在的外接屏 ID 集合（锚点）。
    /// 之后如果这个集合发生了变化（ID 切换、数量变了、被清空），而内置屏仍关着，
    /// 就算 CGDisplayIsActive 仍然对外接返回 true，也视为用户动过外接屏 → 立即恢复内屏。
    private var extIDsAtBuiltInOff: Set<CGDirectDisplayID>? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        appDelegateRef = self
        NSApp.setActivationPolicy(.accessory)

        // 启动时立刻把关键诊断信息打出来，方便通过终端启动看日志定位问题
        print("[DisplayToggle] 启动...")
        let all = DisplayManager.known()
        print("[DisplayToggle] known()=\(all.count) 块, active=\(DisplayManager.activeCount()) 块")
        for d in all {
            print(String(format: "  → id=%-5u  %@  builtIn=%d  active=%d",
                         d.id, d.name, d.isBuiltIn ? 1 : 0, d.isActive ? 1 : 0))
        }
        if let b = DisplayManager.builtIn() {
            print("[DisplayToggle] builtIn 找到: id=\(b.id) active=\(b.isActive)")
        } else {
            print("[DisplayToggle] ⚠️  builtIn 没找到！")
        }
        print("[DisplayToggle] NativeSPI.isAvailable=\(NativeSPI.isAvailable)")
        if !NativeSPI.isAvailable, let err = NativeSPI.dlErrorMessage {
            print("[DisplayToggle]   原因: \(err)")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "DisplayToggle")
            button.image?.isTemplate = true
            button.toolTip = L10n.statusItemToolTip()
        }
        statusItem.menu = menu

        HotKeyCenter.register(keyCode: kToggleKeyCode, nsFlags: kToggleFlags) { [weak self] in
            self?.toggleBuiltIn()
        }

        CGDisplayRegisterReconfigurationCallback({ display, flags, _ in
            DispatchQueue.main.async { appDelegateRef?.handleChange(display: display, flags: flags) }
        }, nil)

        // 额外监听：NSApplication 屏幕参数变化通知（比 CG 回调更高层，某些 macOS 版本更可靠）
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.checkAutoRestore(via: "notification")
            }
        }

        // 轮询兜底：每 2 秒检查一次，确保即使回调/通知都没触发也能自动恢复
        startPolling()

        if Preferences.launchAtLogin { LaunchAtLogin.setEnabled(true) }

        rebuildMenu()

        if HotKeyCenter.usingFallback {
            print("[DisplayToggle] 快捷键走 NSEvent 兜底，需要授予「辅助功能」权限")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 取消待执行的自动切换
        pendingAuto?.cancel()
        // 停止轮询
        stopPolling()
        // 注销全局快捷键
        HotKeyCenter.unregister()
        // 恢复所有被关闭的显示器
        print("[DisplayToggle] 程序退出，恢复所有被关闭的显示器...")
        var restoredIDs = Set<CGDirectDisplayID>()
        for d in DisplayManager.known() where !d.isActive {
            print("[DisplayToggle]   恢复：\(d.name) (id=\(d.id))")
            _ = DisplayController.setDisplay(id: d.id, on: true, fallbackName: d.name)
            restoredIDs.insert(d.id)
        }
        // 兜底：如果 known() 里查不到已禁用的内置屏（CGDisplayIsBuiltin 返回了 -1），
        // 但我们有 lastKnownBuiltInID 且它当前是 inactive，就用缓存 ID 再恢复一次。
        if let cached = Preferences.lastKnownBuiltInID,
           !restoredIDs.contains(cached),
           CGDisplayIsActive(cached) == 0 {
            print("[DisplayToggle]   ⚠️  兜底恢复内置屏（使用缓存 ID=\(cached)）")
            _ = DisplayController.setDisplay(id: cached, on: true, fallbackName: "内置显示器")
        }
    }

    // MARK: 菜单

    private func rebuildMenu() {
        menu.removeAllItems()

        let builtIn = DisplayManager.builtIn()
        let isOn = builtIn?.isActive ?? true
        let active = DisplayManager.activeCount()
        let builtInLockable = isOn && active <= 1   // 内屏是最后一块亮着的屏 → 禁止关闭

        menu.addItem(disabled(L10n.Menu.statusLine(isOn: isOn, active: active)))
        menu.addItem(.separator())

        let toggleTitle = isOn
            ? (builtInLockable ? L10n.Menu.turnBuiltInOffLocked() : L10n.Menu.turnBuiltInOff())
            : L10n.Menu.turnBuiltInOn()
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleBuiltIn), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = !builtInLockable
        menu.addItem(toggle)
        menu.addItem(.separator())

        menu.addItem(disabled(L10n.Menu.allDisplaysHeader()))
        for d in DisplayManager.known() {
            // 最后一块还在输出的屏不允许关闭，否则误操作就是两块全黑
            let locked = d.isActive && active <= 1
            let tail = locked ? "  \(L10n.Menu.lockedLastDisplay())" : ""
            let item = NSMenuItem(
                title: "    " + d.label + tail,
                action: #selector(toggleDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: d.id)
            item.state = d.isActive ? .on : .off
            item.isEnabled = !locked
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // 语言切换
        let langItem = NSMenuItem(title: L10n.Menu.languageMenuTitle(), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for lang in Language.allCases {
            let item = NSMenuItem(title: lang.labelInNative, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.rawValue
            item.state = (L10n.current.rawValue == lang.rawValue) ? .on : .off
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // 后端
        let backendItem = NSMenuItem(title: L10n.Menu.backend(), action: nil, keyEquivalent: "")
        let backendMenu = NSMenu()
        for b in Backend.allCases {
            let item = NSMenuItem(title: b.title, action: #selector(chooseBackend(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = b.rawValue
            item.state = (b.rawValue == Preferences.backend) ? .on : .off
            backendMenu.addItem(item)
        }
        backendItem.submenu = backendMenu
        menu.addItem(backendItem)

        let autoItem = NSMenuItem(title: L10n.Menu.autoDisableBuiltIn(),
                                  action: #selector(toggleAutoDisable(_:)), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = Preferences.autoDisableBuiltIn ? .on : .off
        menu.addItem(autoItem)

        let restoreItem = NSMenuItem(title: L10n.Menu.autoRestoreBuiltIn(),
                                     action: #selector(toggleAutoRestore(_:)), keyEquivalent: "")
        restoreItem.target = self
        restoreItem.state = Preferences.autoRestoreBuiltIn ? .on : .off
        menu.addItem(restoreItem)

        let loginItem = NSMenuItem(title: L10n.Menu.launchAtLogin(),
                                   action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let testItem = NSMenuItem(title: L10n.Menu.selftest(),
                                  action: #selector(runSelfTest), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)

        let aboutItem = NSMenuItem(title: L10n.Menu.about(), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem(title: L10n.Menu.quit(), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// 语言选择回调 —— 立即持久化并重建菜单（同时也会刷新 tooltip）
    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let lang = Language(rawValue: raw) else { return }
        L10n.current = lang
        // tooltip 也要刷新
        if let button = statusItem?.button { button.toolTip = L10n.statusItemToolTip() }
        rebuildMenu()
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: 动作

    /// 【统一关内屏入口】——所有"主动关闭内置屏"的路径（菜单「关闭内置屏」、快捷键切换到关、--off、--selftest、runSelfTest）
    /// 必须经过这里，保证：① 设置 3 秒冷却期  ② **关内屏成功之后立刻记录 NSScreen 外接集合锚点**。
    ///
    /// 设计说明（遵循第二轮基线）：
    ///   - 锚点设置在 setBuiltIn(on:false) 返回成功之后，而不是之前。
    ///   - 虽然 setBuiltIn 会同步触发一批回调，但此时 ignoreChangeUntil=+3s，
    ///     这些回调中的 callback-work 和 notification 都会被冷却期跳过，不产生实际影响。
    ///   - 冷却期过后（约 3 秒），轮询每 1 秒一次的 checkAutoRestore 才是真正的主力判断，
    ///     此时锚点已经设置好 → 条件1/2/3/4 就能正常工作。
    ///   - 这就是上一版（第二轮）拔扩展坞 HDMI 能成功恢复的核心机制：
    ///         拔 HDMI → NSScreen 清空外接 → 条件1（!hasScreeningExternal）在冷却期过后被轮询命中。
    @discardableResult
    private func turnBuiltInOff() -> ToggleOutcome {
        ignoreChangeUntil = Date().addingTimeInterval(3)
        let before = DisplayManager.screeningExternals()
        let result = DisplayController.setBuiltIn(on: false)
        report(result)
        if result.isOK {
            extIDsAtBuiltInOff = before
            let ids = before.map { String($0) }.sorted().joined(separator: ",")
            print("[DisplayToggle] [anchor] 关内屏成功，锚定 NSScreen 外接集合={\(ids)}（冷却期3秒后由轮询兜底判断是否需恢复）")
        } else {
            extIDsAtBuiltInOff = nil
        }
        refresh()
        return result
    }

    /// 【统一开内屏入口】——与 turnBuiltInOff 成对，开内屏成功后清理锚点。
    @discardableResult
    private func turnBuiltInOn() -> ToggleOutcome {
        ignoreChangeUntil = Date().addingTimeInterval(3)
        let result = DisplayController.setBuiltIn(on: true)
        report(result)
        if result.isOK { extIDsAtBuiltInOff = nil }
        refresh()
        return result
    }

    @objc private func toggleBuiltIn() {
        // ⚠️ 重要：不要单独写 ignoreChangeUntil / 锚点 / 清理锚点逻辑，
        //        全部交给 turnBuiltInOff() / turnBuiltInOn() 统一处理，保证所有入口行为一致。
        let isOn = DisplayManager.builtIn()?.isActive ?? true
        if isOn {
            turnBuiltInOff()
        } else {
            turnBuiltInOn()
        }
    }

    @objc private func toggleDisplay(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let id = CGDirectDisplayID(num.uint32Value)
        guard let d = DisplayManager.known().first(where: { $0.id == id }) else { return }
        ignoreChangeUntil = Date().addingTimeInterval(3)
        report(DisplayController.setDisplay(d, on: !d.isActive))
        refresh()
    }

    @objc private func chooseBackend(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        Preferences.backend = raw
        refresh()
    }

    @objc private func toggleAutoDisable(_ sender: NSMenuItem) {
        Preferences.autoDisableBuiltIn.toggle()
        refresh()
    }

    @objc private func toggleAutoRestore(_ sender: NSMenuItem) {
        Preferences.autoRestoreBuiltIn.toggle()
        refresh()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let next = !LaunchAtLogin.isEnabled
        LaunchAtLogin.setEnabled(next)
        Preferences.launchAtLogin = next
        refresh()
    }

    @objc private func runSelfTest() {
        guard DisplayManager.activeCount() >= 2 else {
            alert("无法自检", "正在输出的显示器不足 2 块。请先接上外接显示器。")
            return
        }
        // 统一走 turnBuiltInOff：设置冷却期 + 锚点（保持与用户手动关内屏一致的行为）
        let off = turnBuiltInOff()
        guard off.isOK else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let on = self.turnBuiltInOn()
            if !on.isOK {
                self.alert("恢复失败", "\(on.message)\n\n合上再打开笔记本盖子即可强制恢复。")
            }
        }
    }

    @objc private func showAbout() {
        let flags = "⌃⌥⌘D"
        let body =
            L10n.About.subtitle() + "\n\n" +
            L10n.About.shortcutLine(flags) + "\n" +
            L10n.About.nativeAPILine(available: NativeSPI.isAvailable) + "\n" +
            L10n.About.shortcutModeLine(usingFallback: HotKeyCenter.usingFallback) + "\n\n" +
            L10n.About.emergencyRecovery()
        alert(L10n.About.title(version: "1.1"), body)
    }

    // MARK: 显示器变化

    func handleChange(display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        let raw = flags.rawValue
        let added      = raw & DisplayChange.add.rawValue != 0
        let removed    = raw & DisplayChange.remove.rawValue != 0
        let disabled   = raw & DisplayChange.disabled.rawValue != 0
        let enabled    = raw & DisplayChange.enabled.rawValue != 0
        // macOS 26 在拔线时会额外抛 0x01000(begin) / 0x02000(commit) 等组合事件，
        // 放宽匹配：只要不是纯 desktopShapeChanged/setParams 这类无意义事件，
        // 有 add/remove/enabled/disabled 之外的 0x001220/0x00111e 位也纳入。
        let meaningful = added || removed || disabled || enabled
            || (raw & 0x001000 != 0)   // mirrored 变化
            || (raw & 0x01000 != 0)   // begin config（往往紧跟拔线枚举）
            || (raw & 0x02000 != 0)   // commit config
            || (raw & 0x00100 != 0)   // colorTable 改变（枚举时常伴生）

        let autoEnabled = Preferences.autoDisableBuiltIn || Preferences.autoRestoreBuiltIn
        guard autoEnabled, meaningful else {
            refresh()
            return
        }

        print("[DisplayToggle] [callback] ⚡️ 收到变化事件: display=\(display) flags=0x\(String(raw, radix: 16)) add=\(added) remove=\(removed) en=\(enabled) dis=\(disabled)")

        pendingAuto?.cancel()

        // 延后执行：回调是在发起方的事务期间送达的，立刻再开一个事务会撞车，
        // 可能把对方的改动冲掉。等它落定再说。
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard Date() > self.ignoreChangeUntil else {
                print("[DisplayToggle] [callback-work] ⏳ 被 ignoreChangeUntil 跳过（手动操作冷却期）")
                return
            }

            let ctx = DisplayManager.currentRestoreContext()
            print("[DisplayToggle] [callback-work] 🔎 快照: \(ctx)")

            // 【核心】计算"是否需要恢复内置屏" —— 多重条件，任意一条命中就恢复
            var reason: String? = nil
            if Preferences.autoRestoreBuiltIn, let builtInID = ctx.builtInID {
                let builtInReallyOff = !ctx.builtInPresentInNSScreen
                let anchorStr = self.extIDsAtBuiltInOff?.map { String($0) }.sorted().joined(separator: ",") ?? "(nil)"
                print("[DisplayToggle] [callback-work]    builtInReallyOff=\(builtInReallyOff)  anchor={\(anchorStr)}")

                // 条件 1：NSScreen 层面已经没有任何外接在输出 + 内屏真的暗了
                if builtInReallyOff && !ctx.hasScreeningExternal {
                    reason = "[条件1] NSScreen 已无外接输出 且 内屏暗"
                }
                // 条件 2：存在锚点，且当前 NSScreen 外接集合 ≠ 锚点（包括大小变了 / ID 完全换掉）
                else if builtInReallyOff, let anchor = self.extIDsAtBuiltInOff, !anchor.isEmpty, anchor != ctx.screenExtIDs {
                    let before = anchor.map { String($0) }.sorted().joined(separator: ",")
                    let after  = ctx.screenExtIDs.map { String($0) }.sorted().joined(separator: ",")
                    reason = "[条件2] 锚定外接集合变化: {\(before)} → {\(after)}"
                }
                // 条件 3：存在锚点，当前 screenExt 与 anchor「没有交集」
                //   → 典型幻影屏：锚定的是真外接 id=2，但当前 NSScreen 里只有 id=8（拔线后系统捏造的幻影），
                //     二者完全不重叠 → 用户已经没有任何一块"锚定时真实存在的外接屏"了
                else if builtInReallyOff, let anchor = self.extIDsAtBuiltInOff, !anchor.isEmpty {
                    let intersection = anchor.intersection(ctx.screenExtIDs)
                    if intersection.isEmpty && !ctx.screenExtIDs.isEmpty {
                        let before = anchor.map { String($0) }.sorted().joined(separator: ",")
                        let after  = ctx.screenExtIDs.map { String($0) }.sorted().joined(separator: ",")
                        reason = "[条件3] 当前外接屏ID与锚定集合完全无交集: {\(before)} ∩ {\(after)} = ∅（全是幻影屏）"
                    }
                }
                // 条件 4：activeCount==0，完全黑屏
                if builtInReallyOff && ctx.activeCount == 0 && reason == nil {
                    reason = "[条件4] activeCount=0，用户彻底黑屏"
                }

                if let r = reason {
                    print("[DisplayToggle] [callback-work] ✅ → 命中恢复条件：\(r)")
                    print("[DisplayToggle] [callback-work]    调用 setDisplay(id:\(builtInID), on:true)...")
                    let result = DisplayController.setDisplay(id: builtInID, on: true, fallbackName: "内置显示器")
                    print("[DisplayToggle] [callback-work]    恢复结果: ok=\(result.isOK) msg=\(result.message)")
                    if !result.isOK {
                        print("[DisplayToggle] [callback-work]    🔁 首次失败，再试 setBuiltIn(on:true) ...")
                        let r2 = DisplayController.setBuiltIn(on: true)
                        print("[DisplayToggle] [callback-work]    二次: ok=\(r2.isOK) msg=\(r2.message)")
                    }
                    if result.isOK { self.extIDsAtBuiltInOff = nil }
                } else {
                    print("[DisplayToggle] [callback-work] ⏭  未命中任何恢复条件。")
                }
            } else if !Preferences.autoRestoreBuiltIn {
                print("[DisplayToggle] [callback-work] ⏭  autoRestore 关闭，跳过恢复判断。")
            } else {
                print("[DisplayToggle] [callback-work] ❌ 无法获取内置屏 ID，放弃。")
            }

            // 4) 自动关闭：有外接屏 + 内屏亮着 + 至少 2 块屏 → 自动关内屏（默认关闭，用户按需开启）
            if Preferences.autoDisableBuiltIn,
               let builtInID = ctx.builtInID,
               ctx.builtInPresentInNSScreen,
               ctx.hasScreeningExternal,
               ctx.activeCount >= 2 {
                print("[DisplayToggle] [callback-work] → 命中 autoDisable，关内屏 id=\(builtInID)")
                _ = DisplayController.setDisplay(id: builtInID, on: false, fallbackName: "内置显示器")
            }

            self.refresh()
        }
        pendingAuto = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        refresh()
    }

    // MARK: 轮询兜底

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)     // 从 2s → 1s，兜底更及时
        timer.setEventHandler { [weak self] in
            self?.checkAutoRestore(via: "poll")
        }
        timer.resume()
        pollTimer = timer
        print("[DisplayToggle] 🔁 轮询兜底已启动（每 1 秒）")
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    /// 检查是否需要自动恢复内置屏（轮询和通知共用）
    /// 与 handleChange 的判断逻辑保持一致，保证三重路径判据对齐。
    private func checkAutoRestore(via source: String) {
        guard Preferences.autoRestoreBuiltIn else {
            if source != "poll" { print("[DisplayToggle] [\(source)] autoRestore 未开启，跳过。") }
            return
        }
        guard Date() > ignoreChangeUntil else {
            if source != "poll" { print("[DisplayToggle] [\(source)] ⏳ 手动操作冷却期内，跳过。") }
            return
        }

        let ctx = DisplayManager.currentRestoreContext()

        var hit = false
        var reason: String? = nil
        if ctx.builtInID != nil {
            let builtInReallyOff = !ctx.builtInPresentInNSScreen

            if builtInReallyOff && !ctx.hasScreeningExternal {
                hit = true
                reason = "[条件1] NSScreen 已无外接输出且内屏暗"
            } else if builtInReallyOff, let anchor = extIDsAtBuiltInOff, !anchor.isEmpty, anchor != ctx.screenExtIDs {
                hit = true
                let before = anchor.map { String($0) }.sorted().joined(separator: ",")
                let after  = ctx.screenExtIDs.map { String($0) }.sorted().joined(separator: ",")
                reason = "[条件2] 锚定外接集合变化: {\(before)} → {\(after)}"
            } else if builtInReallyOff, let anchor = extIDsAtBuiltInOff, !anchor.isEmpty {
                let intersection = anchor.intersection(ctx.screenExtIDs)
                if intersection.isEmpty && !ctx.screenExtIDs.isEmpty {
                    hit = true
                    let before = anchor.map { String($0) }.sorted().joined(separator: ",")
                    let after  = ctx.screenExtIDs.map { String($0) }.sorted().joined(separator: ",")
                    reason = "[条件3] 外接屏ID与锚定完全无交集(幻影): {\(before)} ∩ {\(after)} = ∅"
                }
            }
            if builtInReallyOff && ctx.activeCount == 0 && reason == nil {
                hit = true
                reason = "[条件4] activeCount=0"
            }
        }

        if hit {
            print("[DisplayToggle] [\(source)] 🔎 命中 → \(ctx)")
        } else if source != "poll" {
            print("[DisplayToggle] [\(source)] 🔎 未命中 → \(ctx)")
        }

        if hit, let builtInID = ctx.builtInID, let r = reason {
            print("[DisplayToggle] [\(source)] ✅ → 自动恢复内置屏 id=\(builtInID) 原因: \(r)")
            let result = DisplayController.setDisplay(id: builtInID, on: true, fallbackName: "内置显示器")
            print("[DisplayToggle] [\(source)]    结果: ok=\(result.isOK) msg=\(result.message)")
            if !result.isOK {
                print("[DisplayToggle] [\(source)]    🔁 首次失败，再试 setBuiltIn(on:true) ...")
                let r2 = DisplayController.setBuiltIn(on: true)
                print("[DisplayToggle] [\(source)]    二次: ok=\(r2.isOK) msg=\(r2.message)")
            }
            if result.isOK { extIDsAtBuiltInOff = nil }
            refresh()
        }
    }

    // MARK: 辅助

    private func refresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.rebuildMenu() }
    }

    private func report(_ outcome: ToggleOutcome) {
        print("[DisplayToggle] " + outcome.message)
        if !outcome.isOK {
            NSSound.beep()
            if case .refused(let reason) = outcome { alert(L10n.Alert.refused(), reason) }
            if case .failed(let detail) = outcome { alert(L10n.Alert.failed(), detail) }
        }
    }

    private func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = title
        a.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

// MARK: - 启动

// 关掉 stdout 缓冲：日志重定向到文件时能实时落盘，进程被终止也不会丢
setbuf(stdout, nil)

let args = Array(CommandLine.arguments.dropFirst())
if let first = args.first, CLIEntry.handle(args) {
    _ = first
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
