# DisplayToggle

一个常驻菜单栏的 macOS 小工具：**在笔记本开盖的状态下，彻底关掉内置屏**，只留外接显示器。

用系统私有 API `CGSConfigureDisplayEnabled` 实现（开源工具 displayplacer 的同一套思路），
不依赖 BetterDisplay / Lunar，也不需要付费。

---

## 它能做什么

| 功能 | 说明 |
|---|---|
| 一键开关内置屏 | 菜单栏点击，或全局快捷键 **⌃⌥⌘D** |
| 单独控制任意一块屏 | 菜单里列出所有显示器，逐块开关 |
| 关掉的屏还能找回来 | 被禁用的屏依然列在菜单里（标「已关闭」），点一下即可恢复 |
| 接上外接屏自动关内屏 | 默认开启；外接屏撤掉后自动恢复内屏 |
| 开机自启 | 菜单里勾选即可 |
| 三种后端可切换 | 系统原生 / BetterDisplay CLI / Lunar CLI |
| 安全闸 | 最后一块还在输出的屏幕**不允许关闭** —— 菜单项会直接变灰并标注「最后一块屏，禁止关闭」，后端也再做一次拦截 |

## 它不能做什么

BetterDisplay Pro 是一整套显示管理套件，下面这些**本工具没有**，也没有计划做：

- HiDPI 柔性缩放、分辨率档位微调
- XDR / HDR 亮度超频
- 虚拟屏（dummy display）
- DDC/CI 外接显示器亮度控制
- EDID 覆写、色彩模式、画中画、布局保护

如果你的需求正好是这些，直接买 BetterDisplay 更划算（约 $22 买断）。
本工具只专注解决「开盖关屏」这一件事，并且做得足够干净。

---

## 构建

需要 Xcode Command Line Tools（`xcode-select --install`）。

```bash
./build.sh
```

产出 `DisplayToggle.app`（ad-hoc 签名，本机可直接双击运行）。

## 使用

```bash
open DisplayToggle.app
```

首次运行会在菜单栏出现一个显示器图标。右键（或左键）点开即可操作。

### 命令行模式

```bash
BIN="DisplayToggle.app/Contents/MacOS/DisplayToggle"

$BIN --list                  # 列出所有显示器（含已关闭的）+ 后端状态
$BIN --off                   # 关闭内置屏
$BIN --on                    # 恢复内置屏
$BIN --display 2 off         # 关闭 id=2 那块屏（id 用 --list 查）
$BIN --display 2 on          # 恢复 id=2 那块屏
$BIN --selftest              # 关 3 秒再自动恢复（需至少 2 块屏正在输出）
$BIN --help
```

`--off` / `--on` / `--display` 可以直接挂到 Raycast、skhd、Hammerspoon、快捷指令上自己组合快捷键。

> 被关闭的显示器仍然会出现在 `--list` 里（标记为「已关闭」），名称和分辨率也都还在，
> 所以随时能点回来。

### 自检

```bash
DisplayToggle.app/Contents/MacOS/DisplayToggle --selftest
```

关掉内置屏 3 秒再自动恢复。

已在 **macOS 27 (Mac17,5 / Apple A18 Pro) + 3440×1440 外接屏** 上实测通过：
关闭与恢复都返回 success，活动屏数在 2↔1 之间正确变化，菜单栏程序全程存活无崩溃。

换机器或换显示器时建议仍跑一次 —— 极少数机型/接口下可能恢复不回来，早发现比用到一半黑屏好。

---

## 后端说明

| 后端 | 依赖 | 备注 |
|---|---|---|
| 系统原生 | 无 | 默认。用 SkyLight 私有 API，运行时 dlsym 解析，符号不存在会自动降级 |
| BetterDisplay CLI | BetterDisplay Pro | 需要 Pro 授权 + Apple Silicon。内置屏名称不匹配时，改 `Preferences.betterDisplayNamePattern`（默认 `Built-in`） |
| Lunar CLI | Lunar Pro | 走 `lunar displays builtin blackOutEnabled`；BlackOut 属 Pro 功能 |

自动模式下的优先级：**系统原生 → BetterDisplay → Lunar**。
想固定用某个后端，菜单栏「后端」里选即可。

---

## 建议的配套系统设置

1. **把外接屏设为主显示器**：系统设置 → 显示器 → 排列，把顶部白条拖到外接屏上。
2. **关闭「显示器具有单独的空间」**：系统设置 → 桌面与程序坞 → 调度中心。
   否则内屏撤掉后，留在那块屏上的窗口会跟着一起看不见。

---

## 应急恢复

| 情况 | 怎么办 |
|---|---|
| 快捷键没反应 | 看「关于」里是否走了 NSEvent 兜底。是的话需要在 系统设置 → 隐私与安全性 → 辅助功能 里勾选本程序 |
| 内屏关掉后恢复不了 | **合上再打开笔记本盖子**，内置屏必定回来 |
| 自检报恢复失败 | 同上；说明你的机型上系统原生后端不稳，改用 BetterDisplay 后端 |
| 想把程序彻底移除 | 退出程序 + 删除 `DisplayToggle.app` + `defaults delete com.local.displaytoggle` |

---

## 实现要点（踩过的两个坑）

**1. `CGSConfigureDisplayEnabled` 的第一个参数是配置事务句柄，不是连接 ID。**

正确姿势是三段式：

```
CGBeginDisplayConfiguration(&config)
CGSConfigureDisplayEnabled(config, displayID, enabled)   // 第一个参数是 CGSConfigData*
CGCompleteDisplayConfiguration(config, .forSession)
```

如果按很多资料里写的那样直接传 `CGSMainConnectionID()`，函数会把连接 ID 当指针解引用，
立刻 `EXC_BAD_ACCESS` 崩溃（进程退出码 139），崩溃栈落在
`checkCapacity(CGSConfigData*) ← SLSConfigureDisplayEnabled`。

**2. 显示器被禁用后，会从 `CGGetOnlineDisplayList` 里彻底消失 —— 外接屏也一样。**

所以关屏之后不能靠"在线列表"去找它，否则永远恢复不了。但实测发现：

| 状态 | `CGDisplayIsBuiltin(id)` | 分辨率 |
|---|---|---|
| 显示器存在（无论开关） | `0`（外接）或 `1`（内置） | 有效 |
| id 不存在 | `-1` | `0x0` |

也就是说 **`isBuiltin != -1` 即"这个 id 有效"**，被禁用的外接屏同样扫得出来。
程序据此扫 id 1...32，把已关闭的屏重新列进菜单，随时能点回来。
（名称与分辨率会在屏亮着时缓存一份，否则关掉之后 `NSScreen` 就查不到了。）

**3. 两个进程同时开「显示器配置事务」会互相冲掉。**

`CGBeginDisplayConfiguration` → `CGSConfigureDisplayEnabled` → `CGCompleteDisplayConfiguration`
这套事务不是并发安全的。实测中，菜单栏程序若在收到变更回调时立刻去"恢复内屏"，
就会把另一个进程刚提交的"打开外接屏"冲掉，表现为外接屏恢复失败。

对策两条：动作前先判断目标状态（内屏本来就开着就完全不动，不开事务）；
以及把自动动作延后 1.5 秒执行且可取消，等发起方的事务落定。

**4. 用私有 API 做的开关，不会广播给其他进程。**

实测：本进程关屏时，本进程的 `CGDisplayRegisterReconfigurationCallback` 会收到回调
（`remove` + `disabled` 置位），但**其他进程收不到**；而"重新打开"这步干脆不发回调。
所以「插拔外接屏自动开关内屏」依赖真实硬件热插拔事件。

**5. 外屏被拔掉时，回调里的 `CGDisplayIsBuiltin(display)` 返回无效值。**

显示器被物理拔掉后，它的 id 立刻失效，`CGDisplayIsBuiltin(id)` 不再返回 0 或 1，
而是 `-1`（arm64）或 `0xFFFFFFFF`（x86_64）。如果在回调里用它来判断「这是不是外接屏」，
就会判断错误，导致「外屏拔掉后自动恢复内屏」的逻辑被完全跳过。

**正确做法**：不在回调入口处判断单块屏的类型，而是在延迟执行的 block 中
根据系统**整体状态**（`DisplayManager.activeExternals()` 是否为空、内置屏是否激活）
来决定动作。这样无论是热插拔还是软件开关触发的回调，都能正确响应。

## 源码结构

```
Sources/
  main.swift        菜单栏 UI、CLI 入口、显示器热插拔回调、开机自启
  Displays.swift    显示器枚举（CGGetOnlineDisplayList + NSScreen 名称）
  Backends.swift    三种后端 + 安全闸
  HotKey.swift      Carbon 全局快捷键，失败时降级 NSEvent
  Preferences.swift UserDefaults 封装
```

在 macOS 27 (arm64) / Swift 6.4 下编译验证通过。
