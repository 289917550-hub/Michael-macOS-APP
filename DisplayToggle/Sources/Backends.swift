import Foundation
import CoreGraphics

// MARK: - 后端选择

enum Backend: String, CaseIterable, Identifiable {
    case auto
    case native
    case betterDisplay
    case lunar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:          return L10n.BackendL10n.auto()
        case .native:        return L10n.BackendL10n.native()
        case .betterDisplay: return L10n.BackendL10n.betterDisplay()
        case .lunar:         return L10n.BackendL10n.lunar()
        }
    }
}

// MARK: - 后端一：系统原生（SkyLight 私有 API）

/// 通过 dlsym 运行时解析，不产生链接期依赖；符号不存在时优雅降级。
/// 与开源工具 displayplacer 同一套思路，但不依赖任何第三方安装。
struct NativeOutcome {
    let ok: Bool
    let begin: Int32
    let configure: Int32
    let commit: Int32

    var detail: String { "begin=\(begin) configure=\(configure) commit=\(commit)" }
}

enum NativeSPI {

    /// 第一个参数是 CGSConfigData*（由 CGBeginDisplayConfiguration 产出），**不是**连接 ID。
    /// 少了 begin/commit 这两步，函数会把连接 ID 当指针解引用，直接 EXC_BAD_ACCESS 崩溃。
    private typealias ConfigEnabledFn = @convention(c) (OpaquePointer?, CGDirectDisplayID, Bool) -> Int32

    private static let handle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    }()

    /// dlsym 的错误信息（符号找不到时 dlerror() 会返回原因）
    static var dlErrorMessage: String? {
        guard let _ = handle else {
            let e = dlerror()
            return e.map { String(cString: $0) } ?? "dlopen 返回 nil，无法定位 SkyLight.framework"
        }
        guard let _ = dlsym(handle, "CGSConfigureDisplayEnabled") else {
            let e = dlerror()
            return e.map { String(cString: $0) } ?? "dlsym 返回 nil，符号 CGSConfigureDisplayEnabled 未找到"
        }
        return nil
    }

    private static let configFn: ConfigEnabledFn? = {
        guard let h = handle, let s = dlsym(h, "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(s, to: ConfigEnabledFn.self)
    }()

    static var isAvailable: Bool { configFn != nil }

    static func setEnabled(_ display: CGDirectDisplayID, _ enabled: Bool) -> NativeOutcome {
        guard let cfg = configFn else {
            return NativeOutcome(ok: false, begin: -1, configure: -1, commit: -1)
        }

        var config: CGDisplayConfigRef?
        let beginErr = Int32(CGBeginDisplayConfiguration(&config).rawValue)
        guard beginErr == 0, let config else {
            return NativeOutcome(ok: false, begin: beginErr, configure: -1, commit: -1)
        }

        let cfgErr = cfg(config, display, enabled)
        guard cfgErr == 0 else {
            CGCancelDisplayConfiguration(config)
            return NativeOutcome(ok: false, begin: beginErr, configure: cfgErr, commit: -1)
        }

        let commitErr = Int32(CGCompleteDisplayConfiguration(config, .forSession).rawValue)
        return NativeOutcome(ok: commitErr == 0,
                             begin: beginErr, configure: cfgErr, commit: commitErr)
    }

    // MARK: 诊断信息

    static func diagnosePrint() {
        print("🔧 [系统原生后端 (SkyLight SPI) 诊断]")
        let fwPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        let fwExists = FileManager.default.fileExists(atPath: fwPath)
        // 注：新 macOS 版本会把 SkyLight 放进 dyld 共享缓存，磁盘上不再有独立文件，
        // 所以 fwExists=false 是正常的，只要 dlopen 成功就代表可加载。
        print("    SkyLight.framework 独立文件 = \(fwExists ? "存在" : "不存在（已并入 dyld 共享缓存，正常）")")
        print("    dlopen handle = \(handle == nil ? "❌ nil" : "✅ \(handle!)")")
        print("    dlsym(CGSConfigureDisplayEnabled) = \(configFn == nil ? "❌ 未找到" : "✅ 已解析")")
        if let msg = dlErrorMessage {
            print("    dlerror() = \(msg)")
        }
        print("    isAvailable = \(isAvailable)")

        if isAvailable {
            // 做一次「空跑」：begin + 立刻 commit，不改任何显示器
            // 用来验证 begin/commit 这对 API 本身是否正常
            print("    └ 空跑 begin→commit 测试...")
            var cfg: CGDisplayConfigRef?
            let beginErr = CGBeginDisplayConfiguration(&cfg)
            if beginErr != .success {
                print("      ❌ CGBeginDisplayConfiguration 失败，error=\(beginErr.rawValue)")
            } else if cfg == nil {
                print("      ❌ CGBeginDisplayConfiguration 返回了 nil config")
            } else {
                let commitErr = CGCompleteDisplayConfiguration(cfg!, .forSession)
                if commitErr == .success {
                    print("      ✅ begin→commit 空跑成功（显示配置 API 可用）")
                } else {
                    print("      ❌ CGCompleteDisplayConfiguration 失败，error=\(commitErr.rawValue)")
                    // 额外尝试 cancel 看看能不能拿到更多线索
                    let cancelErr = CGCancelDisplayConfiguration(cfg!)
                    print("        (cancel 尝试: error=\(cancelErr.rawValue))")
                }
            }
        }

        print("🔧 [外部工具后端可用性]")
        let bd = CLI.locate(["betterdisplaycli"]) ?? CLI.locateAppBinary("BetterDisplay")
        print("    BetterDisplay CLI = \(bd ?? "❌ 未安装")")
        let ln = CLI.locate(["lunar"])
        print("    Lunar CLI = \(ln ?? "❌ 未安装")")
    }
}

// MARK: - 后端二/三：外部工具 CLI

enum CLI {

    static func locate(_ names: [String]) -> String? {
        let extraDirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            NSHomeDirectory() + "/.local/bin",
        ]
        for name in names {
            if let p = which(name) { return p }
            for dir in extraDirs {
                let full = dir + "/" + name
                if FileManager.default.isExecutableFile(atPath: full) { return full }
            }
        }
        return nil
    }

    static func locateAppBinary(_ appName: String) -> String? {
        let path = "/Applications/\(appName).app/Contents/MacOS/\(appName)"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private static func which(_ name: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = [name]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? nil : s
    }

    @discardableResult
    static func run(_ exe: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return (127, error.localizedDescription) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return (p.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - 执行结果

enum ToggleOutcome {
    case ok(backend: String)
    case refused(reason: String)
    case failed(detail: String)

    var message: String {
        switch self {
        case .ok(let b):       return "已通过「\(b)」完成"
        case .refused(let r):  return r
        case .failed(let d):   return d
        }
    }
    var isOK: Bool { if case .ok = self { return true } else { return false } }
}

// MARK: - 控制器

enum DisplayController {

    /// 打开或关闭指定显示器。内置安全闸：不允许关掉最后一块还在输出的屏幕。
    static func setDisplay(_ d: DisplayInfo, on: Bool) -> ToggleOutcome {
        setDisplay(id: d.id, on: on, fallbackName: d.name)
    }

    /// 按 id 直接操作（用于命令行、以及菜单里已禁用的屏）。
    /// 注意这里用 CGDisplayIsActive 现查，不信任传进来的快照，避免状态过期。
    static func setDisplay(id: CGDirectDisplayID, on: Bool, fallbackName: String? = nil) -> ToggleOutcome {
        if !on {
            let active = DisplayManager.activeCount()
            let isCurrentlyOn = CGDisplayIsActive(id) != 0
            if isCurrentlyOn && active <= 1 {
                return .refused(reason: "只剩这一块屏在输出，关掉就彻底没有画面了。操作已阻止。")
            }
        }

        switch resolvedBackend() {
        case .native:
            guard NativeSPI.isAvailable else {
                return .failed(detail: "本机未找到 CGSConfigureDisplayEnabled 符号")
            }
            let r = NativeSPI.setEnabled(id, on)
            return r.ok ? .ok(backend: "系统原生")
                        : .failed(detail: "系统原生 API 失败（\(r.detail)）")

        case .betterDisplay:
            return betterDisplay(on: on)
                ?? .failed(detail: "找不到 betterdisplaycli 或 BetterDisplay.app。请先安装 BetterDisplay。")

        case .lunar:
            return lunar(on: on)
                ?? .failed(detail: "找不到 lunar 命令行。请先安装 Lunar，并执行 Lunar 菜单里的 Install CLI。")

        case .auto:
            if NativeSPI.isAvailable {
                let native = NativeSPI.setEnabled(id, on)
                if native.ok { return .ok(backend: "系统原生") }
                if let r = betterDisplay(on: on), r.isOK { return r }
                if let r = lunar(on: on), r.isOK { return r }
                return .failed(detail: "系统原生 API 失败（\(native.detail)），且 BetterDisplay / Lunar 也不可用")
            }
            if let r = betterDisplay(on: on), r.isOK { return r }
            if let r = lunar(on: on), r.isOK { return r }
            return .failed(detail: "没有可用后端：本机缺少 CGSConfigureDisplayEnabled，也未安装 BetterDisplay / Lunar。")
        }
    }

    /// 内置屏便捷入口
    static func setBuiltIn(on: Bool) -> ToggleOutcome {
        guard let d = DisplayManager.builtIn() else {
            return .refused(reason: "没找到内置显示器（这是台台式机？）")
        }
        return setDisplay(d, on: on)
    }

    private static func resolvedBackend() -> Backend {
        let raw = Preferences.backend
        return Backend(rawValue: raw) ?? .auto
    }

    private static func betterDisplay(on: Bool) -> ToggleOutcome? {
        guard let exe = CLI.locate(["betterdisplaycli"]) ?? CLI.locateAppBinary("BetterDisplay") else {
            return nil
        }
        let pattern = Preferences.betterDisplayNamePattern
        let r = CLI.run(exe, ["set", "--namelike=\(pattern)", "--connected=\(on ? "on" : "off")"])
        return r.status == 0
            ? .ok(backend: "BetterDisplay")
            : .failed(detail: "BetterDisplay 执行失败（需 Pro 授权 + Apple Silicon）：\(r.output)")
    }

    private static func lunar(on: Bool) -> ToggleOutcome? {
        guard let exe = CLI.locate(["lunar"]) else { return nil }
        // Lunar 的语义是 blackOutEnabled：想让屏幕亮着，就要把它设为 false
        let r = CLI.run(exe, ["displays", "builtin", "blackOutEnabled", on ? "false" : "true"])
        return r.status == 0
            ? .ok(backend: "Lunar")
            : .failed(detail: "Lunar 执行失败（BlackOut 属 Pro 功能）：\(r.output)")
    }
}
