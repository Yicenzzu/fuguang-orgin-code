using System.Drawing.Drawing2D;

namespace Fuguang.Windows;

internal sealed class ScreenshotOverlayForm : Form
{
    private readonly Bitmap screenImage;
    private readonly Rectangle screenBounds;
    private Point dragStart;
    private Rectangle selection;
    private bool dragging;

    public ScreenshotOverlayForm(Bitmap screenImage, Rectangle screenBounds)
    {
        this.screenImage = screenImage;
        this.screenBounds = screenBounds;

        Bounds = screenBounds;
        StartPosition = FormStartPosition.Manual;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        DoubleBuffered = true;
        KeyPreview = true;
        Cursor = Cursors.Cross;

        SetStyle(
            ControlStyles.AllPaintingInWmPaint
            | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.ResizeRedraw
            | ControlStyles.UserPaint,
            true);
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        Activate();
        Focus();
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left)
        {
            base.OnMouseDown(e);
            return;
        }

        dragging = true;
        dragStart = e.Location;
        selection = Rectangle.Empty;
        Invalidate();
        base.OnMouseDown(e);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (dragging)
        {
            selection = Normalize(dragStart, e.Location);
            Invalidate();
        }

        base.OnMouseMove(e);
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left && dragging)
        {
            dragging = false;
            selection = Normalize(dragStart, e.Location);
            Invalidate();
        }

        base.OnMouseUp(e);
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData == Keys.Escape)
        {
            DialogResult = DialogResult.Cancel;
            Close();
            return true;
        }

        if (keyData == Keys.Enter && selection.Width > 0 && selection.Height > 0)
        {
            CopySelectionToClipboard();
            DialogResult = DialogResult.OK;
            Close();
            return true;
        }

        return base.ProcessCmdKey(ref msg, keyData);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.DrawImage(screenImage, Point.Empty);

        using var overlayBrush = new SolidBrush(Color.FromArgb(120, 18, 24, 34));
        e.Graphics.FillRectangle(overlayBrush, ClientRectangle);

        if (selection.Width > 0 && selection.Height > 0)
        {
            e.Graphics.DrawImage(screenImage, selection, selection, GraphicsUnit.Pixel);

            using var borderPen = new Pen(Color.FromArgb(120, 224, 244, 255), 2f);
            e.Graphics.DrawRectangle(borderPen, selection);

            var sizeText = $"{selection.Width} x {selection.Height}";
            DrawHint(e.Graphics, sizeText, new Point(selection.Left, Math.Max(12, selection.Top - 36)));
        }

        DrawHint(e.Graphics, "拖拽框选截图区域，按 Enter 复制到剪贴板，Esc 取消", new Point(16, 16));
        base.OnPaint(e);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            screenImage.Dispose();
        }

        base.Dispose(disposing);
    }

    private void CopySelectionToClipboard()
    {
        using var bitmap = new Bitmap(selection.Width, selection.Height);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.DrawImage(
            screenImage,
            new Rectangle(0, 0, bitmap.Width, bitmap.Height),
            selection,
            GraphicsUnit.Pixel);
        Clipboard.SetImage((Bitmap)bitmap.Clone());
    }

    private static Rectangle Normalize(Point start, Point end)
    {
        var left = Math.Min(start.X, end.X);
        var top = Math.Min(start.Y, end.Y);
        var right = Math.Max(start.X, end.X);
        var bottom = Math.Max(start.Y, end.Y);
        return Rectangle.FromLTRB(left, top, right, bottom);
    }

    private static void DrawHint(Graphics graphics, string text, Point location)
    {
        using var backgroundBrush = new SolidBrush(Color.FromArgb(170, 12, 16, 24));
        using var foregroundBrush = new SolidBrush(Color.White);
        using var font = new Font(FontFamily.GenericSansSerif, 10, FontStyle.Bold);

        var size = TextRenderer.MeasureText(text, font);
        var bounds = new Rectangle(location.X, location.Y, size.Width + 16, size.Height + 10);
        using var path = RoundedRectangle(bounds, 10);
        graphics.FillPath(backgroundBrush, path);
        TextRenderer.DrawText(
            graphics,
            text,
            font,
            new Rectangle(bounds.X + 8, bounds.Y + 5, bounds.Width - 16, bounds.Height - 10),
            foregroundBrush.Color,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
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
