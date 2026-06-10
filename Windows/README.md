# Fuguang Windows

这是 Fuguang 的 Windows 原生客户端起点，使用 .NET 8 WinForms 实现。它与 macOS 版共享产品概念，但不复用 AppKit/Carbon/ScreenCaptureKit 代码。

## 当前能力

- Windows 托盘常驻，双击托盘图标打开主窗口。
- 可视化键盘面板，点击键帽配置动作。
- 已配置键位注册为 `Ctrl + 键` 全局快捷键。
- 支持打开应用、文件夹、网站。
- 支持基础内置动作：显示桌面、截取主屏并保存/复制、剪贴板预览、锁屏。

## 当前限制

- 暂未实现 macOS 版“单独按下并松开组合键打开主界面”的行为。
- 截图目前是主屏全屏截图，不包含 macOS 版选区和标注工具。
- “浮光改图”在 Windows 版中还只是占位提示。
- 该工程需要在 Windows 或安装了 .NET SDK 的环境中构建验证。

## 构建

```powershell
cd Windows\Fuguang.Windows
dotnet build -c Release
```

发布单文件可执行程序：

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```
