import Foundation

// MARK: - 语言与统一翻译表
//
// 设计原则：
//   * 菜单栏、关于弹窗、后端标题、显示器标签等「GUI 文本」全部走 L10n。
//   * 终端日志（print/[DisplayToggle] 前缀）和报警文案仍使用中文为主，
//     开发者读日志时中文足够清楚，避免和 macOS 系统 API 返回值混杂时增加歧义。
//   * 语言切换后立即调用 rebuildMenu() 重建所有菜单项即可，无需重启。

enum Language: String, CaseIterable, Identifiable {
    case zh = "zh"
    case en = "en"
    var id: String { rawValue }

    /// 子菜单中显示的「该语言名称」（始终用语言自己显示，比如 English 不会写成"英文"）
    var labelInNative: String {
        switch self {
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }
}

/// 当前 UI 语言。设置后会持久化。
enum L10n {

    static var current: Language {
        get { Language(rawValue: Preferences.language) ?? .zh }
        set { Preferences.language = newValue.rawValue }
    }

    // MARK: - 状态行 / 菜单项
    enum Menu {
        /// 第一行：内置屏状态 + 正在输出数量
        ///   占位：$ON（开/关 On/Off）、$ACTIVE（正在输出块数）
        static func statusLine(isOn: Bool, active: Int) -> String {
            switch current {
            case .zh: return "内置屏：\(isOn ? "开" : "关")    正在输出：\(active) 块"
            case .en: return "Built-in: \(isOn ? "On" : "Off")    Active displays: \(active)"
            }
        }

        /// 「所有显示器（点击可切换）」的分组标题
        static func allDisplaysHeader() -> String {
            switch current {
            case .zh: return "所有显示器（点击可切换）"
            case .en: return "All displays (click to toggle)"
            }
        }

        /// 单个显示器锁定文案：最后一块亮着的屏禁止关闭
        static func lockedLastDisplay() -> String {
            switch current {
            case .zh: return "—— 最后一块屏，禁止关闭"
            case .en: return "—— last active, cannot turn off"
            }
        }

        /// 切换动作：关内屏（没锁定）
        static func turnBuiltInOff() -> String {
            switch current {
            case .zh: return "关闭内置屏"
            case .en: return "Turn Built-in Off"
            }
        }

        /// 切换动作：关内屏（锁定提示）
        static func turnBuiltInOffLocked() -> String {
            switch current {
            case .zh: return "关闭内置屏（最后一块屏，已锁定）"
            case .en: return "Turn Built-in Off (last active, locked)"
            }
        }

        /// 切换动作：恢复内屏
        static func turnBuiltInOn() -> String {
            switch current {
            case .zh: return "恢复内置屏"
            case .en: return "Turn Built-in On"
            }
        }

        /// 后端子菜单标题
        static func backend() -> String {
            switch current {
            case .zh: return "后端"
            case .en: return "Backend"
            }
        }

        static func autoDisableBuiltIn() -> String {
            switch current {
            case .zh: return "接上外接屏时自动关闭内置屏"
            case .en: return "Auto turn built-in off when external is plugged in"
            }
        }

        static func autoRestoreBuiltIn() -> String {
            switch current {
            case .zh: return "外屏拔掉时自动恢复内置屏"
            case .en: return "Auto restore built-in when external is unplugged"
            }
        }

        static func launchAtLogin() -> String {
            switch current {
            case .zh: return "开机时启动"
            case .en: return "Launch at Login"
            }
        }

        static func selftest() -> String {
            switch current {
            case .zh: return "自检（关 3 秒自动恢复）"
            case .en: return "Self-test (off for 3s, then restore)"
            }
        }

        static func about() -> String {
            switch current {
            case .zh: return "关于"
            case .en: return "About"
            }
        }

        static func quit() -> String {
            switch current {
            case .zh: return "退出"
            case .en: return "Quit"
            }
        }

        /// 「语言 / Language」子菜单标题（中英都写上，避免用户在英语里找不到"语言"在哪）
        static func languageMenuTitle() -> String {
            switch current {
            case .zh: return "语言 / Language"
            case .en: return "Language / 语言"
            }
        }
    }

    // MARK: - 后端 Backend 标题
    enum BackendL10n {
        static func auto() -> String {
            switch current {
            case .zh: return "自动"
            case .en: return "Auto"
            }
        }
        static func native() -> String {
            switch current {
            case .zh: return "系统原生（私有 API）"
            case .en: return "Native (Private SPI)"
            }
        }
        static func betterDisplay() -> String {
            switch current {
            case .zh: return "BetterDisplay CLI"
            case .en: return "BetterDisplay CLI"
            }
        }
        static func lunar() -> String {
            switch current {
            case .zh: return "Lunar CLI"
            case .en: return "Lunar CLI"
            }
        }
    }

    // MARK: - DisplayInfo.label 的部件
    enum DisplayL10n {
        static func builtIn() -> String {
            switch current {
            case .zh: return "内置"
            case .en: return "Built-in"
            }
        }
        static func external() -> String {
            switch current {
            case .zh: return "外接"
            case .en: return "External"
            }
        }
        static func main() -> String {
            switch current {
            case .zh: return "主屏"
            case .en: return "Main"
            }
        }
        static func off() -> String {
            switch current {
            case .zh: return "已关闭"
            case .en: return "Off"
            }
        }
        static func builtInMonitorFallback() -> String {
            switch current {
            case .zh: return "内置显示器"
            case .en: return "Built-in Display"
            }
        }
        static func externalMonitorFallback() -> String {
            switch current {
            case .zh: return "显示器"
            case .en: return "Display"
            }
        }
    }

    // MARK: - 关于弹窗
    enum About {
        static func title(version: String) -> String {
            "DisplayToggle \(version)"
        }
        static func subtitle() -> String {
            switch current {
            case .zh: return "开盖状态下开关 MacBook 内置屏。"
            case .en: return "Turn the MacBook built-in display on / off while the lid is open."
            }
        }
        static func shortcutLine(_ keys: String) -> String {
            switch current {
            case .zh: return "快捷键：\(keys)"
            case .en: return "Shortcut: \(keys)"
            }
        }
        static func nativeAvailable() -> String {
            switch current {
            case .zh: return "可用"
            case .en: return "Available"
            }
        }
        static func nativeUnavailable() -> String {
            switch current {
            case .zh: return "不可用"
            case .en: return "Unavailable"
            }
        }
        static func nativeAPILine(available: Bool) -> String {
            let a = available ? nativeAvailable() : nativeUnavailable()
            switch current {
            case .zh: return "系统原生 API：\(a)"
            case .en: return "Native SPI: \(a)"
            }
        }
        static func carbonShortcutMode() -> String {
            switch current {
            case .zh: return "Carbon"
            case .en: return "Carbon"
            }
        }
        static func fallbackShortcutMode() -> String {
            switch current {
            case .zh: return "NSEvent（需辅助功能权限）"
            case .en: return "NSEvent (needs Accessibility permission)"
            }
        }
        static func shortcutModeLine(usingFallback: Bool) -> String {
            let m = usingFallback ? fallbackShortcutMode() : carbonShortcutMode()
            switch current {
            case .zh: return "快捷键模式：\(m)"
            case .en: return "Shortcut mode: \(m)"
            }
        }
        static func emergencyRecovery() -> String {
            switch current {
            case .zh:
                return "应急恢复：合上再打开笔记本盖子，内置屏必定回来。"
            case .en:
                return "Emergency recovery: close and re-open the laptop lid — the built-in display always comes back."
            }
        }
    }

    // MARK: - 报警弹窗标题（report/refused/failed 只有 GUI 弹窗部分需要国际化，日志仍中文）
    enum Alert {
        static func refused() -> String {
            switch current {
            case .zh: return "已阻止"
            case .en: return "Blocked"
            }
        }
        static func failed() -> String {
            switch current {
            case .zh: return "执行失败"
            case .en: return "Failed"
            }
        }
    }

    // MARK: - statusItem.toolTip（悬停提示）
    static func statusItemToolTip() -> String {
        switch current {
        case .zh: return "DisplayToggle — ⌃⌥⌘D 开关内置屏"
        case .en: return "DisplayToggle — ⌃⌥⌘D to toggle built-in display"
        }
    }
}
