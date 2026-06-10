namespace Fuguang.Windows;

internal sealed class BindingEditorForm : Form
{
    private readonly ComboBox kindBox = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly TextBox titleBox = new();
    private readonly TextBox targetBox = new();
    private readonly Button browseButton = new() { Text = "浏览..." };

    public BindingEditorForm(ShortcutBinding binding)
    {
        Binding = new ShortcutBinding
        {
            Key = binding.Key,
            Kind = binding.Kind,
            Title = binding.Title,
            Target = binding.Target
        };

        Text = $"设置 {binding.Key}";
        Width = 460;
        Height = 250;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MaximizeBox = false;
        MinimizeBox = false;

        kindBox.DataSource = Enum.GetValues<ShortcutActionKind>()
            .Select(kind => new ActionKindItem(kind, kind.Title()))
            .ToArray();
        kindBox.SelectedItem = ((ActionKindItem[])kindBox.DataSource).First(item => item.Kind == Binding.Kind);
        kindBox.SelectedIndexChanged += (_, _) => UpdateTargetControls();

        titleBox.Text = Binding.Title;
        targetBox.Text = Binding.Target;
        browseButton.Click += (_, _) => BrowseTarget();

        var okButton = new Button { Text = "保存", DialogResult = DialogResult.OK };
        var cancelButton = new Button { Text = "取消", DialogResult = DialogResult.Cancel };
        okButton.Click += (_, _) => ApplyChanges();

        AcceptButton = okButton;
        CancelButton = cancelButton;

        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(16),
            ColumnCount = 3,
            RowCount = 5
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 72));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 84));

        layout.Controls.Add(new Label { Text = "动作", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
        layout.Controls.Add(kindBox, 1, 0);
        layout.SetColumnSpan(kindBox, 2);
        layout.Controls.Add(new Label { Text = "名称", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 1);
        layout.Controls.Add(titleBox, 1, 1);
        layout.SetColumnSpan(titleBox, 2);
        layout.Controls.Add(new Label { Text = "目标", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 2);
        layout.Controls.Add(targetBox, 1, 2);
        layout.Controls.Add(browseButton, 2, 2);

        var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft };
        buttons.Controls.Add(okButton);
        buttons.Controls.Add(cancelButton);
        layout.Controls.Add(buttons, 0, 4);
        layout.SetColumnSpan(buttons, 3);

        Controls.Add(layout);
        UpdateTargetControls();
    }

    public ShortcutBinding Binding { get; }

    private ShortcutActionKind SelectedKind => ((ActionKindItem)kindBox.SelectedItem!).Kind;

    private void UpdateTargetControls()
    {
        var requiresTarget = SelectedKind is ShortcutActionKind.OpenApplication
            or ShortcutActionKind.OpenFolder
            or ShortcutActionKind.OpenWebsite
            or ShortcutActionKind.ImageQuickLook;

        targetBox.Enabled = requiresTarget;
        browseButton.Enabled = SelectedKind is ShortcutActionKind.OpenApplication
            or ShortcutActionKind.OpenFolder
            or ShortcutActionKind.ImageQuickLook;
    }

    private void BrowseTarget()
    {
        if (SelectedKind == ShortcutActionKind.OpenFolder)
        {
            using var dialog = new FolderBrowserDialog();
            if (dialog.ShowDialog(this) == DialogResult.OK)
            {
                targetBox.Text = dialog.SelectedPath;
            }

            return;
        }

        using var openDialog = new OpenFileDialog();
        openDialog.Filter = SelectedKind == ShortcutActionKind.OpenApplication
            ? "程序 (*.exe)|*.exe|所有文件 (*.*)|*.*"
            : "图片文件|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.webp|所有文件 (*.*)|*.*";

        if (openDialog.ShowDialog(this) == DialogResult.OK)
        {
            targetBox.Text = openDialog.FileName;
        }
    }

    private void ApplyChanges()
    {
        Binding.Kind = SelectedKind;
        Binding.Title = titleBox.Text.Trim();
        Binding.Target = targetBox.Text.Trim();
    }

    private sealed record ActionKindItem(ShortcutActionKind Kind, string Title)
    {
        public override string ToString() => Title;
    }
}
