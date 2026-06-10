using System.Diagnostics;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Fuguang.Windows;

internal static class ActionRunner
{
    public static void Run(ShortcutBinding binding, IWin32Window owner)
    {
        if (!binding.IsConfigured)
        {
            MessageBox.Show(owner, $"{binding.Key} 尚未设置动作", "Fuguang", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        try
        {
            switch (binding.Kind)
            {
                case ShortcutActionKind.OpenApplication:
                case ShortcutActionKind.OpenFolder:
                    OpenShellTarget(binding.Target);
                    break;
                case ShortcutActionKind.OpenWebsite:
                    OpenShellTarget(NormalizedUrl(binding.Target));
                    break;
                case ShortcutActionKind.ShowDesktop:
                    ToggleDesktop();
                    break;
                case ShortcutActionKind.Screenshot:
                    CapturePrimaryScreen();
                    break;
                case ShortcutActionKind.ImageResize:
                    MessageBox.Show(owner, "Windows 版浮光改图正在迁移中。", "Fuguang", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    break;
                case ShortcutActionKind.ImageQuickLook:
                    OpenShellTarget(binding.Target);
                    break;
                case ShortcutActionKind.Clipboard:
                    ShowClipboard(owner);
                    break;
                case ShortcutActionKind.LockScreen:
                    LockWorkStation();
                    break;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(owner, ex.Message, "动作执行失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private static void OpenShellTarget(string target)
    {
        Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
    }

    private static string NormalizedUrl(string rawValue)
    {
        var trimmed = rawValue.Trim();
        if (Uri.TryCreate(trimmed, UriKind.Absolute, out var url) && !string.IsNullOrWhiteSpace(url.Scheme))
        {
            return trimmed;
        }

        return $"https://{trimmed}";
    }

    private static void CapturePrimaryScreen()
    {
        var bounds = Screen.PrimaryScreen?.Bounds ?? throw new InvalidOperationException("未找到主屏幕。");
        using var bitmap = new Bitmap(bounds.Width, bounds.Height);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);

        Clipboard.SetImage((Bitmap)bitmap.Clone());

        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        var fileName = $"FuguangScreenshot_{DateTime.Now:yyyyMMdd_HHmmss}.png";
        bitmap.Save(Path.Combine(desktop, fileName), ImageFormat.Png);
    }

    private static void ShowClipboard(IWin32Window owner)
    {
        var message = "剪贴板暂无可预览内容。";
        if (Clipboard.ContainsText())
        {
            message = Clipboard.GetText();
            if (message.Length > 800)
            {
                message = message[..800];
            }
        }
        else if (Clipboard.ContainsImage())
        {
            message = "剪贴板中有图片内容。";
        }
        else if (Clipboard.ContainsFileDropList())
        {
            var files = Clipboard.GetFileDropList().Cast<string>();
            message = string.Join(Environment.NewLine, files);
        }

        MessageBox.Show(owner, message, "浮光剪贴", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private static void ToggleDesktop()
    {
        var shellType = Type.GetTypeFromProgID("Shell.Application");
        if (shellType == null)
        {
            throw new InvalidOperationException("无法调用 Windows Shell。");
        }

        dynamic shell = Activator.CreateInstance(shellType)!;
        shell.ToggleDesktop();
    }

    [DllImport("user32.dll")]
    private static extern bool LockWorkStation();
}
