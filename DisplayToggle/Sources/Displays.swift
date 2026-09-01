import Foundation
import AppKit
import CoreGraphics

// MARK: - 显示器数据模型

struct DisplayInfo: Hashable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let isActive: Bool
    let isMain: Bool
    let width: Int
    let height: Int

    var label: String {
        var parts: [String] = [isBuiltIn ? L10n.DisplayL10n.builtIn() : L10n.DisplayL10n.external()]
        if width > 1 { parts.append("\(width)×\(height)") }   // 被禁用的屏会读到 1x1，不展示
        if isMain { parts.append(L10n.DisplayL10n.main()) }
        if !isActive { parts.append(L10n.DisplayL10n.off()) }
        return "\(name)  ·  \(parts.joined(separator: " · "))"
    }
}

// MARK: - 显示器枚举

enum DisplayManager {

    /// 当前真正可用（正在输出画面）的显示器数量
    static func activeCount() -> Int {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        return Int(count)
    }

    /// 在线列表。注意：显示器被禁用后会从这里消失，所以不能只靠它。
    static func online() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        if count == 0 { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)

        let names = nameMap()
        return ids.prefix(Int(count)).map { id in
            let builtIn = CGDisplayIsBuiltin(id) == 1
            return DisplayInfo(
                id: id,
                name: names[id] ?? (builtIn ? L10n.DisplayL10n.builtInMonitorFallback() : "\(L10n.DisplayL10n.externalMonitorFallback()) \(id)"),
                isBuiltIn: builtIn,
                isActive: CGDisplayIsActive(id) != 0,
                isMain: CGDisplayIsMain(id) != 0,
                width: Int(CGDisplayPixelsWide(id)),
                height: Int(CGDisplayPixelsHigh(id))
            )
        }
    }

    /// 扫描 ID 的上限。Apple Silicon 每个大版本都会往高位走，
    /// 这里故意留大一点（扫空 ID 是 O(1) 系统调用，开销可忽略）。
    static let scanMaxID: UInt32 = 1024

    /// 判断某个 display id 是否「存在」（不管是否被禁用）。
    /// 返回 nil 表示不存在，返回 true/false 表示是否内置。
    static func probeID(_ id: CGDirectDisplayID) -> Bool? {
        let flag = CGDisplayIsBuiltin(id)
        if flag == 1 { return true }
        if flag == 0 { return false }
        return nil
    }

    /// 能被程序操作的全部显示器 —— 包括被禁用的。
    static func known() -> [DisplayInfo] {
        var meta = loadMeta()
        var result: [DisplayInfo] = []
        var seen = Set<CGDirectDisplayID>()
        var foundBuiltInID: CGDirectDisplayID? = nil

        for d in online() {
            if d.isActive {
                meta[Int(d.id)] = Meta(name: d.name, width: d.width, height: d.height)
            }
            if d.isBuiltIn { foundBuiltInID = d.id }
            result.append(d)
            seen.insert(d.id)
        }

        for id: CGDirectDisplayID in 1...scanMaxID where !seen.contains(id) {
            guard let builtIn = probeID(id) else { continue }
            if builtIn { foundBuiltInID = id }
            let m = meta[Int(id)]
            result.append(DisplayInfo(
                id: id,
                name: m?.name ?? (builtIn ? L10n.DisplayL10n.builtInMonitorFallback() : "\(L10n.DisplayL10n.externalMonitorFallback()) \(id)"),
                isBuiltIn: builtIn,
                isActive: false,
                isMain: false,
                width: m?.width ?? 0,
                height: m?.height ?? 0
            ))
        }

        saveMeta(meta)

        // 每次枚举到内置屏就把它更新到「兜底缓存」
        if let bid = foundBuiltInID {
            if Preferences.lastKnownBuiltInID != bid {
                Preferences.lastKnownBuiltInID = bid
            }
        }

        return result.sorted { a, b in
            if a.isBuiltIn != b.isBuiltIn { return a.isBuiltIn }
            return a.id < b.id
        }
    }

    static func builtIn() -> DisplayInfo? {
        known().first { $0.isBuiltIn }
    }

    /// 「可靠的」内置屏 ID 获取：先正常查 builtIn()，查不到就用 lastKnownBuiltInID 兜底。
    /// 返回 (id, fromCache) —— 第二个值告诉调用者是不是走了兜底。
    static func resolveBuiltInID() -> (id: CGDirectDisplayID?, fromCache: Bool) {
        if let d = builtIn() { return (d.id, false) }
        if let cached = Preferences.lastKnownBuiltInID {
            print("[DisplayManager] ⚠️  builtIn() 查不到，使用兜底缓存 ID=\(cached)")
            return (cached, true)
        }
        print("[DisplayManager] ❌  既查不到内置屏，也没有兜底缓存。")
        return (nil, false)
    }

    static func activeExternals() -> [DisplayInfo] {
        known().filter { !$0.isBuiltIn && $0.isActive }
    }

    // MARK: - 面向恢复判断的「真实输出」状态查询

    /// 基于 NSScreen.screens 拿到「真的有画面输出」的外接屏 ID 集合。
    ///
    /// 为什么要单独做这个函数：
    ///   CGDisplayIsActive 只是系统内部的"连接层"状态。拔外屏线、重新枚举的瞬间，
    ///   系统可能把外接屏标记为 active 但实际上已经停止输出画面（"幻影屏"），
    ///   这时 hasActiveExternal==true 但外接其实已经不亮，
    ///   自动恢复逻辑的条件就被锁死了。
    /// NSScreen.screens 是 AppKit 的"画面输出层"视图——
    ///   只有真的在渲染画面的屏才会出现在这里，这才是金标准。
    static func screeningExternals() -> Set<CGDirectDisplayID> {
        var result: Set<CGDirectDisplayID> = []
        for s in NSScreen.screens {
            guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = CGDirectDisplayID(num.uint32Value)
            // 排除内置屏
            let f = CGDisplayIsBuiltin(id)
            if f != 1 {
                result.insert(id)
            }
        }
        return result
    }

    /// 把当前「用于恢复判断」的状态打包成一份快照，方便日志和比对。
    struct RestoreContext: CustomStringConvertible {
        let activeCount: Int
        let cgExternals: [CGDirectDisplayID]   // DisplayManager.activeExternals 的 id 列表
        let screenExtIDs: Set<CGDirectDisplayID> // 基于 NSScreen 的真实输出外接
        let builtInID: CGDirectDisplayID?
        let builtInFromCache: Bool
        let builtInActive: Bool   // 用 CGDisplayIsActive(builtInID)
        let builtInPresentInNSScreen: Bool  // builtInID 是否在 NSScreen.screens 中（最可靠的亮屏证明）

        /// 最关键：到底有没有"真的在输出画面的外接屏"
        var hasScreeningExternal: Bool { !screenExtIDs.isEmpty }

        var description: String {
            let bID = builtInID.map { String($0) } ?? "(nil)"
            let cgStr = cgExternals.map { String($0) }.joined(separator: ",")
            let scStr = screenExtIDs.map { String($0) }.sorted().joined(separator: ",")
            return "active=\(activeCount) cgExt=(\(cgStr)) screenExt=(\(scStr)) hasScreenExt=\(hasScreeningExternal) builtIn=\(bID)(cache=\(builtInFromCache)) active=\(builtInActive) inNSScreen=\(builtInPresentInNSScreen)"
        }
    }

    static func currentRestoreContext() -> RestoreContext {
        let activeCount = activeCount()
        let cgExternals = activeExternals().map { $0.id }
        let screenExts = screeningExternals()

        let (bID, fromCache) = resolveBuiltInID()
        let builtInActive: Bool
        let builtInInNS: Bool
        if let bid = bID {
            builtInActive = CGDisplayIsActive(bid) != 0
            // 是否在 NSScreen 里（最可靠的"真的亮着"指标）
            var found = false
            for s in NSScreen.screens {
                guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                if CGDirectDisplayID(n.uint32Value) == bid { found = true; break }
            }
            builtInInNS = found
        } else {
            builtInActive = false
            builtInInNS = false
        }

        return RestoreContext(
            activeCount: activeCount,
            cgExternals: cgExternals,
            screenExtIDs: screenExts,
            builtInID: bID,
            builtInFromCache: fromCache,
            builtInActive: builtInActive,
            builtInPresentInNSScreen: builtInInNS
        )
    }

    // MARK: - 诊断输出（用于 --diagnose）

    /// 打印 CG API 全量诊断信息，供定位「找不到屏 / 内置判断错 / API 不返回」等问题。
    static func diagnosePrint() {
        // 1) 原始计数
        var activeCount: UInt32 = 0
        let errActive = CGGetActiveDisplayList(0, nil, &activeCount)
        var onlineCount: UInt32 = 0
        let errOnline = CGGetOnlineDisplayList(0, nil, &onlineCount)
        print("📊 [CG API 原始计数]")
        print("    CGGetActiveDisplayList → count=\(activeCount)  err=\(errActive.rawValue)")
        print("    CGGetOnlineDisplayList → count=\(onlineCount)  err=\(errOnline.rawValue)")

        // 2) 全量 active id
        if activeCount > 0 {
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(activeCount))
            var real: UInt32 = 0
            _ = CGGetActiveDisplayList(activeCount, &ids, &real)
            print("📊 [Active 明细] 共 \(real) 块：")
            for i in 0..<Int(real) {
                let id = ids[i]
                let fRaw = CGDisplayIsBuiltin(id)
                let f = Int32(truncatingIfNeeded: fRaw)
                print(String(format: "    id=%-5u  builtin_flag=0x%08X(%-4ld)  active=%d  main=%d  %dx%d",
                             id,
                             UInt32(bitPattern: f), Int(f),
                             CGDisplayIsActive(id),
                             CGDisplayIsMain(id),
                             Int(CGDisplayPixelsWide(id)),
                             Int(CGDisplayPixelsHigh(id))))
            }
        }

        // 3) 扫 1...scanMaxID，统计 CGDisplayIsBuiltin 的返回值分布，并打印所有可疑/存在的 id
        print("📊 [扫描范围 1...\(scanMaxID) — CGDisplayIsBuiltin 返回值分布]")
        var hitsByValue: [Int32: Int] = [:]
        var flagged: [(id: UInt32, flag: Int32)] = []
        for id: CGDirectDisplayID in 1...scanMaxID {
            let fRaw = CGDisplayIsBuiltin(id)
            let f = Int32(truncatingIfNeeded: fRaw)
            hitsByValue[f, default: 0] += 1
            // 典型「不存在」：-1。其它值都算可疑，全部打出来。
            if f != -1 {
                flagged.append((id: id, flag: f))
            }
        }
        for (v, c) in hitsByValue.sorted(by: { $0.key < $1.key }) {
            print(String(format: "    flag=0x%08X(%-4ld) → %u 个 id",
                         UInt32(bitPattern: v), Int(v), CUnsignedInt(c)))
        }
        if flagged.isEmpty {
            print("⚠️  所有 id 的 flag 都是 -1，没有识别到任何显示器。")
            print("    可能性：① 进程被沙盒/权限拦截 ② 这台机器真的没有任何 GPU 输出 ③ macOS 版本改了 API 语义")
        } else {
            print("📊 [存在/可疑的 ID 明细] 共 \(flagged.count) 个：")
            for x in flagged {
                let kindDesc = (x.flag == 1) ? "内置✅" : (x.flag == 0 ? "外接" : "⚠️未知")
                let activeDesc = CGDisplayIsActive(x.id) != 0 ? "亮屏" : "关闭"
                let mainDesc = CGDisplayIsMain(x.id) != 0 ? "主屏" : ""
                print(String(format: "    id=%-5u  flag=0x%08X(%-4ld)  %@  %@  %@  %dx%d",
                             x.id,
                             UInt32(bitPattern: x.flag), Int(x.flag),
                             kindDesc, activeDesc, mainDesc,
                             Int(CGDisplayPixelsWide(x.id)),
                             Int(CGDisplayPixelsHigh(x.id))))
            }
        }

        // 4) NSScreen
        print("📊 [NSScreen.screens] 共 \(NSScreen.screens.count) 块：")
        for s in NSScreen.screens {
            guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            print("    id=\(num.uint32Value)  name=\(s.localizedName)  frame=\(s.frame)")
        }

        // 5) 进程身份 & 权限线索
        print("📊 [进程环境]")
        print("    PID = \(getpid())")
        print("    主 bundle = \(Bundle.main.bundlePath)")
        print("    可执行 = \(Bundle.main.executablePath ?? "(null)")")
        #if arch(arm64)
        print("    架构 = arm64 (Apple Silicon)")
        #elseif arch(x86_64)
        print("    架构 = x86_64 (Intel)")
        #else
        print("    架构 = unknown")
        #endif
        if #available(macOS 13.0, *) {
            let vers = ProcessInfo.processInfo.operatingSystemVersionString
            print("    macOS = \(vers)")
        }
        // 辅助功能权限：NSEvent 全局监听需要
        let accessEnabled = AXIsProcessTrusted()
        print("    辅助功能权限 (AXIsProcessTrusted) = \(accessEnabled)")
    }

    // MARK: 私有：名称与分辨率缓存

    private struct Meta: Codable {
        let name: String
        let width: Int
        let height: Int
    }

    private static let metaKey = "displayMetaCache"

    private static func loadMeta() -> [Int: Meta] {
        guard let data = UserDefaults.standard.data(forKey: metaKey),
              let m = try? JSONDecoder().decode([Int: Meta].self, from: data) else { return [:] }
        return m
    }

    private static func saveMeta(_ m: [Int: Meta]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(m), forKey: metaKey)
    }

    private static func nameMap() -> [CGDirectDisplayID: String] {
        var map: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            map[CGDirectDisplayID(num.uint32Value)] = screen.localizedName
        }
        return map
    }
}
