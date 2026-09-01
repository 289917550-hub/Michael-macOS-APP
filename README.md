# Michael-macOS-APP

控制多显示器开启和关闭的 macOS 工具 / A macOS tool to control multiple displays on/off

本仓库当前主程序为 **DisplayToggle**：在笔记本开盖的状态下，彻底关掉内置屏，只留外接显示器。
使用系统私有 API `CGSConfigureDisplayEnabled` 实现（与开源工具 displayplacer 同一套思路），
不依赖 BetterDisplay / Lunar，也不需要付费。

---

## 最新下载 / Latest Release

**当前版本 v1.1.0**（`arm64 + x86_64` 通用二进制，最低 macOS 13.0 Ventura）

| 文件 | 用途 |
|---|---|
| `DisplayToggle-1.1.0.pkg` | ✅ 推荐：安装包，双击会把程序装到 /Applications |
| `DisplayToggle.app` | 绿色版，可直接双击运行，或拖到 /Applications 手动安装 |

> ⚠️ 首次运行 ad-hoc 签名的程序时，若提示「无法打开」，请右键 → 打开（或在系统设置 → 隐私与安全性 → 仍要打开）。
> 这是没有 Apple Developer ID 签名时的标准步骤。

### 历史版本

- `DisplayToggle-1.0.0.pkg` — 初代版本，基本可用，但存在「关内屏后直拔 Type‑C 扩展坞内屏不自动恢复」的 bug，已在 v1.1 修复。

---

## 功能介绍 / Features

| 功能 | 说明 |
|---|---|
| 一键开关内置屏 | 菜单栏点击，或全局快捷键 **⌃⌥⌘D**（Ctrl+Opt+Cmd+D） |
| 单独控制任意一块屏 | 菜单里列出所有显示器，逐块开关 |
| 关掉的屏还能找回来 | 被禁用的屏依然列在菜单里（标「已关闭 / Off」），点一下即可恢复 |
| **内置屏自动恢复**（v1.1 新特性） | 在手动关内屏的情况下，**拔掉 HDMI 线缆** 或 **直接拔掉 Type‑C 扩展坞**，内屏都会自动点亮 |
| 接上外接屏自动关内屏 | 菜单里勾选即可（默认关闭） |
| 开机自启 | 菜单里勾选即可 |
| 三种后端可切换 | 系统原生 / BetterDisplay CLI / Lunar CLI |
| **中英双语菜单**（v1.1 新特性） | 菜单栏「语言 / Language」→ 简体中文 / English，即时生效，无需重启，退出后保留选择 |
| 安全闸 | 最后一块还在输出的屏幕**不允许关闭** —— 菜单项会直接变灰并标注，后端也再做一次拦截 |

---

## 系统要求 / Requirements

- macOS **13.0 (Ventura) 及以上**
- 架构：**Apple Silicon (arm64)** 与 **Intel (x86_64)** 通用二进制
- 建议：外接屏场景（只有一块内置屏的机器本工具意义不大）

## 安装方法 / Installation

1. 下载 `DisplayToggle-1.1.0.pkg`
2. 双击运行安装包（按提示填密码，会装到 /Applications/DisplayToggle.app）
3. 从「应用程序」里打开 DisplayToggle —— 菜单栏右上角会出现一个 🖥️ 图标

或者直接下载 `DisplayToggle.app` 拖到 应用程序。

## 使用方法 / Usage

### 菜单栏操作

左键或右键点击菜单栏里的显示器图标即可打开菜单。菜单内容随「语言 / Language」选择自动切换：

```
【中文菜单】
  内置屏：开    正在输出：2 块
  ──────────
  关闭内置屏
  ──────────
  所有显示器（点击可切换）
      Built-in Retina Display  ·  内置 · 1408×881 · 主屏
      ZQE-CBA  ·  外接 · 3440×1440
  ──────────
  语言 / Language     →  简体中文 ✓ / English
  后端                →  自动 / 系统原生（私有 API）/ BetterDisplay CLI / Lunar CLI
  接上外接屏时自动关闭内置屏
  外屏拔掉时自动恢复内置屏   ← 默认开启（v1.1 修复了直拔 Type‑C 扩展坞不恢复的 bug）
  开机时启动
  ──────────
  自检（关 3 秒自动恢复）
  关于
  退出 ⌘Q

【English Menu】
  Built-in: On    Active displays: 2
  ──────────
  Turn Built-in Off
  ──────────
  All displays (click to toggle)
      Built-in Retina Display  ·  Built-in · 1408×881 · Main
      ZQE-CBA  ·  External · 3440×1440
  ──────────
  Language / 语言  →  简体中文 / English ✓
  Backend           →  Auto / Native (Private SPI) / BetterDisplay CLI / Lunar CLI
  Auto turn built-in off when external is plugged in
  Auto restore built-in when external is unplugged  ← on by default
  Launch at Login
  ──────────
  Self-test (off for 3s, then restore)
  About
  Quit ⌘Q
```

### 命令行模式

```bash
BIN="/Applications/DisplayToggle.app/Contents/MacOS/DisplayToggle"

$BIN --list                  # 列出所有显示器（含已关闭的）+ 后端状态
$BIN --off                   # 关闭内置屏
$BIN --on                    # 恢复内置屏
$BIN --display 2 off         # 关闭 id=2 那块屏（id 用 --list 查）
$BIN --display 2 on          # 恢复 id=2 那块屏
$BIN --selftest              # 关 3 秒再自动恢复（需至少 2 块屏正在输出）
$BIN --diagnose              # 打印完整诊断信息，遇到问题先跑这个，把输出贴给开发者
$BIN --help
```

`--off` / `--on` / `--display` 可以直接挂到 Raycast、skhd、Hammerspoon、快捷指令上自己组合快捷键。

### 应急恢复

如果任何情况下内屏回不来：**合上再打开笔记本盖子**，内置屏必定回来。

---

## 源码 / Source Code

本仓库的 `DisplayToggle/` 目录就是完整的 Swift 源码 + 构建脚本：

```
DisplayToggle/
├── Sources/
│   ├── main.swift           菜单栏 UI、CLI 入口、自动恢复逻辑（幻影屏/锚点集合检测）、快捷键/热插拔
│   ├── Displays.swift       显示器枚举 + NSScreen 真实输出金标准查询 + 诊断
│   ├── Backends.swift       三种后端（系统原生 / BetterDisplay / Lunar）+ 安全闸
│   ├── HotKey.swift         Carbon 全局快捷键（Fallback：NSEvent，需辅助功能权限）
│   ├── Preferences.swift    UserDefaults 偏好（后端/自动开关/启动项/内置ID缓存/语言）
│   └── L10n.swift           中英双语翻译表
├── Info.plist               包配置（LSUIElement=菜单栏程序，不占 Dock）
├── build.sh                 本机架构快速构建（日常开发）
├── package.sh               通用二进制 + .pkg + .dmg 打包脚本
└── README.md                本文件
```

构建需要 Xcode Command Line Tools（`xcode-select --install`）：

```bash
cd DisplayToggle
./build.sh       # 编 DisplayToggle.app
./package.sh     # 编通用二进制 + 打 DisplayToggle-1.1.0.pkg + .dmg
```

---

## 版本信息 / Version

| 版本 | 说明 |
|---|---|
| **1.1.0** | ✅ 修复「关内屏后直拔 Type‑C 扩展坞，内屏不自动恢复」；新增中英双语菜单栏；统一关内屏入口（锚点不会漏记）；boolean_t 类型跨 SDK 兼容修复 |
| 1.0.0 | 初版，基本开关功能可用 |

✅ v1.1.0 实机验证（macOS 26 / M4 MacBook Neo + 3440×1440 外接屏，连接方式：MacBook ←Type‑C← 扩展坞 ←HDMI← 外接屏）：

| 场景 | 操作 | 幻影屏 ID | 命中判断条件 | 结果 |
|---|---|---|---|---|
| A | 关内屏 → 拔扩展坞 HDMI 线 | {2} → {11} | 轮询条件2：锚定集合变化 | ✅ 内屏 6 秒内自动亮 |
| B | 关内屏 → 直拔整条 Type‑C 扩展坞 | {2} → {12} | 轮询条件2：锚定集合变化 | ✅ 内屏 6 秒内自动亮 |
| 双语切换 | 菜单「语言 / Language」切换 | - | 立即 rebuildMenu() + 刷新 tooltip & 关于弹窗 | ✅ |
