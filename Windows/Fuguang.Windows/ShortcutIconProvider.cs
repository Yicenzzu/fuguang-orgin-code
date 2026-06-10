using System.Drawing.Drawing2D;

namespace Fuguang.Windows;

internal static class ShortcutIconProvider
{
    public static Image CreateIcon(ShortcutBinding binding)
    {
        if (binding.Kind == ShortcutActionKind.OpenApplication && File.Exists(binding.Target))
        {
            try
            {
                using var icon = Icon.ExtractAssociatedIcon(binding.Target);
                if (icon != null)
                {
                    return icon.ToBitmap();
                }
            }
            catch
            {
                // Fall back to generated icons for shortcuts that cannot expose an icon.
            }
        }

        return CreateGlyphIcon(GlyphFor(binding.Kind), ColorFor(binding.Kind));
    }

    private static string GlyphFor(ShortcutActionKind kind) => kind switch
    {
        ShortcutActionKind.OpenApplication => "A",
        ShortcutActionKind.OpenFolder => "D",
        ShortcutActionKind.OpenWebsite => "W",
        ShortcutActionKind.ShowDesktop => "H",
        ShortcutActionKind.Screenshot => "S",
        ShortcutActionKind.ImageResize => "I",
        ShortcutActionKind.ImageQuickLook => "V",
        ShortcutActionKind.Clipboard => "C",
        ShortcutActionKind.LockScreen => "L",
        _ => ""
    };

    private static Color ColorFor(ShortcutActionKind kind) => kind switch
    {
        ShortcutActionKind.OpenApplication => Color.FromArgb(245, 199, 50),
        ShortcutActionKind.OpenFolder => Color.FromArgb(247, 180, 38),
        ShortcutActionKind.OpenWebsite => Color.FromArgb(67, 188, 228),
        ShortcutActionKind.ShowDesktop => Color.FromArgb(40, 181, 218),
        ShortcutActionKind.Screenshot => Color.FromArgb(70, 139, 232),
        ShortcutActionKind.ImageResize => Color.FromArgb(224, 74, 92),
        ShortcutActionKind.ImageQuickLook => Color.FromArgb(130, 108, 230),
        ShortcutActionKind.Clipboard => Color.FromArgb(230, 116, 178),
        ShortcutActionKind.LockScreen => Color.FromArgb(76, 84, 101),
        _ => Color.FromArgb(78, 134, 164)
    };

    private static Image CreateGlyphIcon(string glyph, Color color)
    {
        var bitmap = new Bitmap(64, 64);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.Clear(Color.Transparent);

        using var path = RoundedRectangle(new Rectangle(4, 4, 56, 56), 16);
        using var brush = new LinearGradientBrush(new Rectangle(4, 4, 56, 56), Blend(color, Color.White, 0.18), color, 90f);
        graphics.FillPath(brush, path);

        using var borderPen = new Pen(Color.FromArgb(190, 255, 255, 255), 2);
        graphics.DrawPath(borderPen, path);

        TextRenderer.DrawText(
            graphics,
            glyph,
            new Font(FontFamily.GenericSansSerif, 24, FontStyle.Bold),
            new Rectangle(4, 4, 56, 56),
            ForegroundFor(color),
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);

        return bitmap;
    }

    private static Color ForegroundFor(Color color)
    {
        var luminance = (0.299 * color.R) + (0.587 * color.G) + (0.114 * color.B);
        return luminance > 150 ? Color.FromArgb(34, 44, 50) : Color.White;
    }

    private static Color Blend(Color color, Color target, double amount)
    {
        return Color.FromArgb(
            color.A,
            color.R + (int)((target.R - color.R) * amount),
            color.G + (int)((target.G - color.G) * amount),
            color.B + (int)((target.B - color.B) * amount));
    }

    private static GraphicsPath RoundedRectangle(Rectangle bounds, int radius)
    {
        var diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(bounds.X, bounds.Y, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Y, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.X, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}
