import Foundation

enum Preferences {
    private static let suite = UserDefaults.standard

    private enum Key {
        static let backend = "backend"
        static let autoDisable = "autoDisableBuiltInOnExternal"
        static let autoRestore = "autoRestoreBuiltInWhenExternalGone"
        static let launchAtLogin = "launchAtLogin"
        static let bdPattern = "betterDisplayNamePattern"
        static let lastKnownBuiltInID = "lastKnownBuiltInDisplayID"
        static let language = "uiLanguage"
    }

    static var backend: String {
        get { suite.string(forKey: Key.backend) ?? Backend.auto.rawValue }
        set { suite.set(newValue, forKey: Key.backend) }
    }

    /// 接上外接屏时自动关闭内置屏（默认关闭，由用户手动选择）
    static var autoDisableBuiltIn: Bool {
        get { suite.bool(forKey: Key.autoDisable) }
        set { suite.set(newValue, forKey: Key.autoDisable) }
    }

    /// 外接屏全部拔掉时自动恢复内置屏（默认开启，作为安全保护）
    static var autoRestoreBuiltIn: Bool {
        get { suite.object(forKey: Key.autoRestore) == nil ? true : suite.bool(forKey: Key.autoRestore) }
        set { suite.set(newValue, forKey: Key.autoRestore) }
    }

    static var launchAtLogin: Bool {
        get { suite.bool(forKey: Key.launchAtLogin) }
        set { suite.set(newValue, forKey: Key.launchAtLogin) }
    }

    static var betterDisplayNamePattern: String {
        get { suite.string(forKey: Key.bdPattern) ?? "Built-in" }
        set { suite.set(newValue, forKey: Key.bdPattern) }
    }

    // MARK: - UI 语言（zh / en）
    //
    // 没设置时默认跟随系统：系统主语言为英文则 en，否则 zh。
    static var language: String {
        get {
            if let stored = suite.string(forKey: Key.language) { return stored }
            let sys = Locale.preferredLanguages.first ?? "zh"
            return sys.lowercased().hasPrefix("en") ? "en" : "zh"
        }
        set {
            suite.set(newValue, forKey: Key.language)
        }
    }

    // MARK: - 上次已知的内置屏 ID
    //
    // 关键：当内置屏被本程序禁用后，它会从 CGGetOnlineDisplayList 消失，
    // 且某些 macOS 版本 / Apple Silicon 芯片上，CGDisplayIsBuiltin(id)
    // 对已禁用的内置屏不再返回 1，而是返回 -1（认为"不存在"）。
    // 这样 DisplayManager.builtIn() 就查不到了，自动恢复逻辑跟着失效。
    //
    // 解决方案：每次成功找到内置屏时都把 ID 记下来（持久化），
    // 自动恢复时若 builtIn() 查不到，就用这个缓存的 ID 兜底。

    static var lastKnownBuiltInID: UInt32? {
        get {
            let v = suite.object(forKey: Key.lastKnownBuiltInID) as? UInt32
            return (v == nil || v == 0) ? nil : v
        }
        set {
            if let v = newValue, v != 0 {
                suite.set(v, forKey: Key.lastKnownBuiltInID)
                print("[Pref] 记录 lastKnownBuiltInID = \(v)")
            } else {
                suite.removeObject(forKey: Key.lastKnownBuiltInID)
            }
        }
    }
}
