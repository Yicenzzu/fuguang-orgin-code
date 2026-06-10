using System.Drawing.Drawing2D;

namespace Fuguang.Windows;

internal sealed class KeyTile : Control
{
    private bool isPressed;
    private bool isHovered;
    private ShortcutBinding binding = ShortcutBinding.Empty("");
    private Image? iconImage;

    public KeyTile()
    {
        SetStyle(
            ControlStyles.AllPaintingInWmPaint
            | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.ResizeRedraw
            | ControlStyles.SupportsTransparentBackColor
            | ControlStyles.UserPaint,
            true);

        Cursor = Cursors.Hand;
        Font = new Font(FontFamily.GenericSansSerif, 12, FontStyle.Bold);
        BackColor = Color.Transparent;
    }

    public string KeyName { get; set; } = "";

    public ShortcutBinding Binding
    {
        get => binding;
        set
        {
            binding = value;
            Invalidate();
        }
    }

    public Color AccentColor { get; set; } = Color.FromArgb(42, 60, 79, 92);

    public Image? IconImage
    {
        get => iconImage;
        set
        {
            iconImage = value;
            Invalidate();
        }
    }

    protected override void OnMouseEnter(EventArgs e)
    {
        isHovered = true;
        Invalidate();
        base.OnMouseEnter(e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        isHovered = false;
        isPressed = false;
        Invalidate();
        base.OnMouseLeave(e);
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
        {
            isPressed = true;
            Invalidate();
        }

        base.OnMouseDown(e);
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        isPressed = false;
        Invalidate();
        base.OnMouseUp(e);
    }

    protected override void OnGotFocus(EventArgs e)
    {
        Invalidate();
        base.OnGotFocus(e);
    }

    protected override void OnLostFocus(EventArgs e)
    {
        Invalidate();
        base.OnLostFocus(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var graphics = e.Graphics;
        graphics.SmoothingMode = SmoothingMode.AntiAlias;

        var bounds = ClientRectangle;
        bounds.Inflate(-1, -1);
        if (isPressed)
        {
            bounds.Offset(0, 2);
        }

        using var tilePath = RoundedRectangle(bounds, 14);
        var baseColor = Binding.IsConfigured ? AccentColor : Color.FromArgb(76, 112, 148);
        if (isHovered)
        {
            baseColor = Binding.IsConfigured
                ? Blend(baseColor, Color.White, 0.16)
                : Color.FromArgb(92, 132, 172);
        }

        using (var brush = new LinearGradientBrush(
            bounds,
            Binding.IsConfigured ? Blend(baseColor, Color.White, 0.16) : Color.FromArgb(108, 146, 184),
            Binding.IsConfigured ? Blend(baseColor, Color.FromArgb(30, 72, 96), 0.10) : Color.FromArgb(64, 96, 132),
            90f))
        {
            graphics.FillPath(brush, tilePath);
        }

        using (var borderPen = new Pen(Focused
                   ? Color.FromArgb(20, 118, 255)
                   : Color.FromArgb(Binding.IsConfigured ? 210 : 180, 232, 242, 252),
               Focused ? 2.4f : 1.2f))
        {
            graphics.DrawPath(borderPen, tilePath);
        }

        if (Binding.IsConfigured)
        {
            DrawConfiguredContent(graphics, bounds);
        }
        else
        {
            DrawEmptyContent(graphics, bounds);
        }
    }

    private void DrawEmptyContent(Graphics graphics, Rectangle bounds)
    {
        TextRenderer.DrawText(
            graphics,
            KeyName,
            new Font(Font.FontFamily, 14, FontStyle.Bold),
            bounds,
            Color.White,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
    }

    private void DrawConfiguredContent(Graphics graphics, Rectangle bounds)
    {
        var iconSize = Math.Clamp((int)(bounds.Width * 0.42), 28, 48);
        var iconBounds = new Rectangle(
            bounds.X + (bounds.Width - iconSize) / 2,
            bounds.Y + Math.Max(8, bounds.Height / 7),
            iconSize,
            iconSize);

        if (IconImage != null)
        {
            graphics.DrawImage(IconImage, iconBounds);
        }
        else
        {
            TextRenderer.DrawText(
                graphics,
                IconText(Binding.Kind),
                new Font(Font.FontFamily, 11, FontStyle.Bold),
                iconBounds,
                ForegroundFor(AccentColor),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
        }

        var titleBounds = new Rectangle(bounds.X + 5, bounds.Bottom - 30, bounds.Width - 10, 20);
        TextRenderer.DrawText(
            graphics,
            Binding.DisplayTitle,
            new Font(Font.FontFamily, 8, FontStyle.Bold),
            titleBounds,
            ForegroundFor(AccentColor),
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);

        using var markBrush = new SolidBrush(Color.FromArgb(220, 255, 255, 255));
        graphics.FillEllipse(markBrush, bounds.Right - 11, bounds.Bottom - 11, 6, 6);
    }

    private static string IconText(ShortcutActionKind kind) => kind switch
    {
        ShortcutActionKind.OpenApplication => "APP",
        ShortcutActionKind.OpenFolder => "DIR",
        ShortcutActionKind.OpenWebsite => "WEB",
        ShortcutActionKind.ShowDesktop => "HOME",
        ShortcutActionKind.Screenshot => "SHOT",
        ShortcutActionKind.ImageResize => "IMG",
        ShortcutActionKind.ImageQuickLook => "VIEW",
        ShortcutActionKind.Clipboard => "CLIP",
        ShortcutActionKind.LockScreen => "LOCK",
        _ => ""
    };

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

    private Color EffectiveBackgroundColor()
    {
        for (var parent = Parent; parent != null; parent = parent.Parent)
        {
            if (parent.BackColor.A > 0 && parent.BackColor != Color.Transparent)
            {
                return parent.BackColor;
            }
        }

        return Color.FromArgb(238, 247, 255);
    }
}
