using System.Diagnostics;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Fuguang.Windows;

internal static class ActionRunner
{
    private static readonly string[] ImageExtensions =
    [
        ".bmp",
        ".gif",
        ".jpeg",
        ".jpg",
        ".png",
        ".webp"
    ];

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
                    StartScreenCapture(owner);
                    break;
                case ShortcutActionKind.ImageResize:
                    ResizeImage(owner);
                    break;
                case ShortcutActionKind.ImageQuickLook:
                    ShowImagePreview(binding.Target);
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

    private static void StartScreenCapture(IWin32Window owner)
    {
        if (Screen.AllScreens.Length == 0)
        {
            throw new InvalidOperationException("未找到可用屏幕。");
        }

        var bounds = Screen.AllScreens
            .Select(screen => screen.Bounds)
            .Aggregate(Rectangle.Union);
        using var bitmap = new Bitmap(bounds.Width, bounds.Height);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size, CopyPixelOperation.SourceCopy);
        using var overlay = new ScreenshotOverlayForm((Bitmap)bitmap.Clone(), bounds);
        overlay.ShowDialog();
    }

    private static void ShowClipboard(IWin32Window owner)
    {
        if (Clipboard.ContainsText())
        {
            var text = Clipboard.GetText();
            if (text.Length > 2000)
            {
                text = text[..2000] + Environment.NewLine + "……";
            }

            MessageBox.Show(owner, text, "浮光剪贴", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        if (Clipboard.ContainsImage())
        {
            using var image = Clipboard.GetImage();
            if (image != null)
            {
                ImagePreviewForm.ShowImage(null, (Image)image.Clone(), "剪贴板图片");
                return;
            }
        }

        if (Clipboard.ContainsFileDropList())
        {
            var files = Clipboard.GetFileDropList().Cast<string>();
            MessageBox.Show(owner, string.Join(Environment.NewLine, files), "浮光剪贴", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        MessageBox.Show(owner, "剪贴板暂无可预览内容。", "浮光剪贴", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private static void ResizeImage(IWin32Window owner)
    {
        using var source = LoadImageFromClipboard();
        if (source == null)
        {
            MessageBox.Show(owner, "请先复制一张图片，或复制一个图片文件后再触发“浮光改图”。", "浮光改图", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        const int maxEdge = 1600;
        var scale = Math.Min(1.0, (double)maxEdge / Math.Max(source.Width, source.Height));
        if (scale >= 1.0)
        {
            Clipboard.SetImage((Bitmap)source.Clone());
            MessageBox.Show(owner, "图片已经小于 1600px，无需缩放；已重新复制到剪贴板。", "浮光改图", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var width = Math.Max(1, (int)Math.Round(source.Width * scale));
        var height = Math.Max(1, (int)Math.Round(source.Height * scale));
        using var resized = new Bitmap(width, height);
        using (var graphics = Graphics.FromImage(resized))
        {
            graphics.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
            graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
            graphics.DrawImage(source, 0, 0, width, height);
        }

        Clipboard.SetImage((Bitmap)resized.Clone());

        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        var outputPath = Path.Combine(desktop, $"FuguangResized_{DateTime.Now:yyyyMMdd_HHmmss}.png");
        resized.Save(outputPath, ImageFormat.Png);

        MessageBox.Show(owner, $"图片已缩放为 {width} x {height}，保存到桌面并复制到剪贴板。\n\n{outputPath}", "浮光改图", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private static Image? LoadImageFromClipboard()
    {
        if (Clipboard.ContainsImage())
        {
            return Clipboard.GetImage();
        }

        if (!Clipboard.ContainsFileDropList())
        {
            return null;
        }

        var imagePath = Clipboard.GetFileDropList()
            .Cast<string>()
            .FirstOrDefault(IsImageFile);
        return imagePath == null ? null : Image.FromFile(imagePath);
    }

    private static void ShowImagePreview(string path)
    {
        if (!File.Exists(path))
        {
            throw new FileNotFoundException("图片文件不存在。", path);
        }

        if (!IsImageFile(path))
        {
            OpenShellTarget(path);
            return;
        }

        using var image = Image.FromFile(path);
        ImagePreviewForm.ShowImage(null, (Image)image.Clone(), Path.GetFileName(path));
    }

    private static bool IsImageFile(string path)
    {
        return ImageExtensions.Contains(Path.GetExtension(path), StringComparer.OrdinalIgnoreCase);
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
