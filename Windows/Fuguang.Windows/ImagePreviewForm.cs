namespace Fuguang.Windows;

internal sealed class ImagePreviewForm : Form
{
    private readonly Image image;
    private readonly PictureBox pictureBox = new()
    {
        Dock = DockStyle.Fill,
        SizeMode = PictureBoxSizeMode.Zoom,
        BackColor = Color.FromArgb(24, 24, 24)
    };

    private ImagePreviewForm(Image image, string title)
    {
        this.image = image;

        Text = $"浮光图鉴 - {title}";
        StartPosition = FormStartPosition.CenterParent;
        MinimumSize = new Size(420, 300);
        Width = Math.Clamp(image.Width + 40, 520, 1100);
        Height = Math.Clamp(image.Height + 90, 380, 820);

        pictureBox.Image = image;

        var infoLabel = new Label
        {
            Dock = DockStyle.Bottom,
            Height = 34,
            TextAlign = ContentAlignment.MiddleLeft,
            Padding = new Padding(12, 0, 12, 0),
            Text = $"{image.Width} x {image.Height}px"
        };

        Controls.Add(pictureBox);
        Controls.Add(infoLabel);
    }

    public static void ShowImage(IWin32Window? owner, Image image, string title)
    {
        var form = new ImagePreviewForm(image, title);
        if (owner == null)
        {
            form.Show();
            return;
        }

        form.Show(owner);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            pictureBox.Image = null;
            image.Dispose();
        }

        base.Dispose(disposing);
    }
}
