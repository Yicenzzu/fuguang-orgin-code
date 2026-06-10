# Fuguang

Fuguang（浮光）是一款快捷启动工具。它用一个轻量的键盘面板，把常用应用、文件夹、网站和内置工具绑定到键盘按键上，适合快速启动、截图和日常效率操作。

当前仓库包含 Fuguang 的 macOS Swift 源码和 Windows 原生客户端起点；1.0 版本的可安装 DMG 放在 GitHub Releases 中：

- macOS 源码：`Sources/Fuguang/`
- Windows 源码：`Windows/Fuguang.Windows/`
- 1.0 安装包：[Fuguang-1.0.dmg](https://github.com/Yicenzzu/fuguang-orgin-code/releases/download/v1.0/Fuguang-1.0.dmg)

## 核心功能

- 菜单栏常驻，不占用 Dock 图标。
- 可视化键盘主界面，用键帽展示每个快捷键绑定状态。
- 支持 `Control + 按键` 全局快捷键，首次启动默认使用 Control 作为组合键。
- 可在菜单栏或 Dock 菜单中切换组合键：`Option` / `Control`。
- 快速绑定应用、文件夹、网站和浮光内置操作。
- 应用绑定后键帽显示真实 App 图标。
- 文件夹和网址绑定后在键帽内部显示名称。
- 主界面打开时可直接按已配置按键触发动作。
- 单独按下并松开组合键可打开主界面；主界面已打开时再次按下并松开可关闭。
- 若组合键期间触发了具体快捷键动作，则不会再弹出主界面。

## 内置动作

Fuguang 当前支持以下动作类型：

- 打开应用
- 打开文件夹
- 打开网站
- 浮光截图
- 浮光改图
- 浮光图鉴
- 浮光剪贴
- 浮光锁屏

其中“浮光截图”和“浮光改图”已经有较完整的原型实现；“浮光图鉴”和“浮光剪贴”目前仍是后续扩展方向。

## 截图功能

浮光截图是应用内全屏覆盖层截图工具，支持：

- 鼠标所在窗口预选框
- 手动拖拽选区
- 复制到剪贴板
- 保存为 PNG
- 矩形、圆形、箭头、画笔、文字、马赛克标注
- 撤销标注
- 标注颜色切换
- 截图时暂停全局快捷键，避免误触其他绑定
- 截图时不在 Dock 中弹出应用图标

截图采集使用 ScreenCaptureKit，并保留低版本 macOS 的兼容路径。

## 浮光改图

浮光改图窗口支持：

- 批量添加图片
- 图片预览和缩略图列表
- 设置最大宽高并等比缩放
- JPEG / PNG 输出
- JPEG 质量设置
- 输出目录选择
- 批量导出

## 安装 1.0 版本

1.0 版本 DMG 请从 GitHub Releases 下载：

[Fuguang-1.0.dmg](https://github.com/Yicenzzu/fuguang-orgin-code/releases/download/v1.0/Fuguang-1.0.dmg)

打开 DMG 后，将 `Fuguang.app` 拖拽到“应用程序”快捷方式即可安装。

说明：当前安装包使用本地 ad-hoc 签名，适合本机测试和信任设备分发；还不是 Apple Developer ID 公证版本。

## macOS 版本适配

- 最低支持版本：macOS 14 Sonoma。
- 推荐运行版本：macOS 14 或更新版本；在 macOS 15 Sequoia 上可继续运行。
- 截图功能依赖系统屏幕录制权限。首次开启权限后，通常需要完全退出并重新打开 Fuguang，权限状态才会对当前应用进程生效。
- 截图采集优先使用当前系统可用的屏幕捕获能力，并保留兼容路径，以适配不同 macOS 14/15 小版本中的 ScreenCaptureKit 行为差异。
- 全局快捷键使用 Carbon `RegisterEventHotKey`，在 macOS 14+ 上可用于注册 `Control` / `Option` 组合键；部分全局按键监听和权限状态刷新可能受系统安全策略影响。
- 开机启动使用 macOS 现代登录项能力，适配 macOS 14+；修改后可能需要重启应用或重新登录后观察最终状态。

## 构建方式

macOS 项目目前使用 Swift Package 组织：

```bash
swift build
```

Release 构建：

```bash
swift build -c release
```

当前目标平台：

- macOS 14 Sonoma 或更新版本
- Swift 5.10+
- 完整 Xcode 环境推荐

Windows 客户端位于 `Windows/Fuguang.Windows/`，使用 .NET 8 WinForms：

```powershell
cd Windows\Fuguang.Windows
dotnet build -c Release
```

发布 Windows 单文件可执行程序：

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

Windows 版当前是原生客户端起点，已实现托盘、键盘面板、`Ctrl + 键` 全局快捷键、打开应用/文件夹/网站、显示桌面、主屏截图、剪贴板预览和锁屏。截图选区标注、浮光改图等功能仍待继续迁移。

如果 `xcodebuild` 指向 Command Line Tools，可能会遇到 AppKit / SwiftUI SDK 相关问题。建议切换到完整 Xcode：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## 手动打包说明

当前仓库没有标准 Xcode `.xcodeproj`，DMG 是从 SwiftPM release 产物手动组装：

1. `swift build -c release`
2. 创建 `Fuguang.app/Contents/MacOS/Fuguang`
3. 写入 `Info.plist`
4. 写入 `AppIcon.icns`
5. 使用 ad-hoc 签名：

```bash
codesign --force --deep --sign - dist/Fuguang.app
```

6. 创建带“应用程序”快捷方式的 DMG：

```bash
hdiutil create -volname Fuguang -srcfolder dist/dmg-root -ov -format UDZO dist/Fuguang.dmg
```

## 项目结构

```text
Sources/Fuguang/
  FuguangApp.swift                  App 入口、菜单栏、Dock 菜单
  ContentView.swift                 主界面和键盘面板承载
  KeyboardView.swift                键盘键帽显示
  KeyConfigurationView.swift        快捷键绑定菜单
  GlobalHotKeyManager.swift         全局快捷键注册和组合键切换
  ScreenshotOverlayController.swift 截图覆盖层、标注、复制/保存
  ImageToolWindowController.swift   浮光改图窗口
  ActionRunner.swift                动作执行
  ShortcutModels.swift              动作模型和键盘布局
  ShortcutStore.swift               本地配置持久化

Windows/Fuguang.Windows/
  Program.cs                        Windows App 入口
  MainForm.cs                       托盘和键盘面板
  GlobalHotKeyManager.cs            Windows 全局快捷键注册
  ActionRunner.cs                   Windows 动作执行
  ShortcutModels.cs                 动作模型和键盘布局
  ShortcutStore.cs                  本地配置持久化
```

## 权限与注意事项

- 全局快捷键基于 Carbon `RegisterEventHotKey`。
- 截图功能依赖 macOS 屏幕录制权限。
- 部分全局事件监听行为可能受辅助功能权限和系统版本影响。
- 锁屏功能调用系统 `CGSession -suspend`。
- 若后续面向正式分发，需要补充 Developer ID 签名、公证和标准 App 工程配置。

## 当前限制

- 尚未提供标准 Xcode App target。
- 尚未提供自动化测试 target。
- 浮光剪贴仍未实现完整剪贴板历史。
- 浮光图鉴目前仍需升级为独立图片管理/预览体验。
- 当前 DMG 是本地测试包，不是已公证的正式发布包。
- Windows 版仍是第一版原生客户端骨架，尚未完整追平 macOS 版截图标注和改图能力。

## 版本

### 1.0

- 包含当前源码。
- 安装包发布在 GitHub Releases：`v1.0`。
- 默认全局组合键为 `Control + 按键`。
- 支持主界面快捷键切换、截图工具、改图窗口和 DMG 拖拽安装。
