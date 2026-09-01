import Foundation
import AppKit
import Carbon.HIToolbox

private var hotKeyAction: (() -> Void)?

private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ theEvent: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async { hotKeyAction?() }
    return noErr
}

/// 全局快捷键。优先用 Carbon 的 RegisterEventHotKey（无需任何权限），
/// 注册失败时降级为 NSEvent 全局监听（需要「辅助功能」授权）。
enum HotKeyCenter {

    static private(set) var usingFallback = false
    static private(set) var lastError: OSStatus = noErr

    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerInstalled = false

    static func register(keyCode: UInt32,
                         nsFlags: NSEvent.ModifierFlags,
                         action: @escaping () -> Void) {
        hotKeyAction = action

        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            let err = InstallEventHandler(GetApplicationEventTarget(),
                                          carbonHotKeyHandler, 1, &spec, nil, nil)
            handlerInstalled = (err == noErr)
            lastError = err
        }

        if handlerInstalled {
            var carbonMods: UInt32 = 0
            if nsFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if nsFlags.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if nsFlags.contains(.control) { carbonMods |= UInt32(controlKey) }
            if nsFlags.contains(.shift)   { carbonMods |= UInt32(shiftKey) }

            var ref: EventHotKeyRef?
            let err = RegisterEventHotKey(
                keyCode, carbonMods,
                EventHotKeyID(signature: OSType(0x4454_4F47), id: 1),
                GetApplicationEventTarget(), 0, &ref
            )
            if err == noErr {
                hotKeyRef = ref
                return
            }
            lastError = err
        }

        usingFallback = true
        let wanted = nsFlags.intersection([.command, .option, .control, .shift])
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { ev in
            guard UInt32(ev.keyCode) == keyCode else { return }
            guard ev.modifierFlags.intersection([.command, .option, .control, .shift]) == wanted else { return }
            DispatchQueue.main.async { hotKeyAction?() }
        }
    }

    static func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
    }
}
