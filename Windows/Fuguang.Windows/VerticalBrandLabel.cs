namespace Fuguang.Windows;

internal sealed class VerticalBrandLabel : Control
{
    public VerticalBrandLabel()
    {
        SetStyle(
            ControlStyles.AllPaintingInWmPaint
            | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.ResizeRedraw
            | ControlStyles.SupportsTransparentBackColor
            | ControlStyles.UserPaint,
            true);

        Font = new Font(FontFamily.GenericSansSerif, 24, FontStyle.Bold);
        ForeColor = Color.FromArgb(18, 32, 48);
        BackColor = Color.Transparent;
    }

    public string BrandText { get; set; } = "浮光";

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);

        var flags = TextFormatFlags.HorizontalCenter
            | TextFormatFlags.VerticalCenter
            | TextFormatFlags.NoPadding
            | TextFormatFlags.SingleLine;

        var first = BrandText.Length > 0 ? BrandText[0].ToString() : "";
        var second = BrandText.Length > 1 ? BrandText[1].ToString() : "";
        var inner = Rectangle.Inflate(ClientRectangle, -12, -2);
        var halfHeight = inner.Height / 2;

        TextRenderer.DrawText(e.Graphics, first, Font, new Rectangle(inner.X - 6, inner.Y, inner.Width, halfHeight), ForeColor, flags);
        TextRenderer.DrawText(e.Graphics, second, Font, new Rectangle(inner.X + 8, inner.Y + halfHeight, inner.Width, inner.Height - halfHeight), ForeColor, flags);
    }
}
