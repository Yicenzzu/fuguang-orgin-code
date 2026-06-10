namespace Fuguang.Windows;

internal sealed class BindingEditorForm : Form
{
    private readonly ComboBox kindCombo = new();
    private readonly TextBox titleBox = new();
    private readonly TextBox targetBox = new();
    private readonly Label targetLabel = new();

    public BindingEditorForm(ShortcutBinding binding)
    {
        Text = "编辑快捷键";
        Width = 420;
        Height = 320;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MaximizeBox = false;
        MinimizeBox = false;

        var okButton = new Button { Text = "保存" };
        var cancelButton = new Button { Text = "取消", DialogResult = DialogResult.Cancel };
        okButton.Click += (_, _) => SaveAndClose();

        AcceptButton = okButton;
        CancelButton = cancelButton;

        Binding = binding;

        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(16),
            RowCount = 5,
            ColumnCount = 2
        };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 14));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 84));

        foreach (ShortcutActionKind kind in Enum.GetValues<ShortcutActionKind>())
        {
            kindCombo.Items.Add(kind);
        }
        kindCombo.SelectedItem = binding.Kind;
        kindCombo.Dock = DockStyle.Fill;
        kindCombo.SelectedIndexChanged += (_, _) => UpdateTargetVisibility();

        titleBox.Text = binding.Title ?? "";
        titleBox.Dock = DockStyle.Fill;
        titleBox.PlaceholderText = "显示名称";

        targetBox.Text = binding.Target ?? "";
        targetBox.Dock = DockStyle.Fill;
        targetBox.PlaceholderText = GetTargetPlaceholder(binding.Kind);

        targetLabel.Text = "目标";
        targetLabel.Dock = DockStyle.Fill;
        targetLabel.TextAlign = ContentAlignment.MiddleLeft;

        var kindLabel = new Label { Text = "操作类型", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft };
        layout.Controls.Add(kindLabel, 0, 0);
        layout.SetColumnSpan(kindLabel, 2);
        layout.Controls.Add(kindCombo, 0, 1);
        layout.SetColumnSpan(kindCombo, 2);

        var titleLabel = new Label { Text = "名称", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft };
        layout.Controls.Add(titleLabel, 0, 2);
        layout.SetColumnSpan(titleLabel, 2);
        layout.Controls.Add(titleBox, 0, 3);
        layout.SetColumnSpan(titleBox, 2);

        layout.Controls.Add(targetLabel, 0, 4);
        layout.SetColumnSpan(targetLabel, 2);
        layout.Controls.Add(targetBox, 0, 5);
        layout.SetColumnSpan(targetBox, 2);

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            Padding = new Padding(0, 10, 0, 0)
        };
        buttons.Controls.Add(okButton);
        buttons.Controls.Add(cancelButton);
        layout.Controls.Add(buttons, 0, 6);
        layout.SetColumnSpan(buttons, 2);

        Controls.Add(layout);
        UpdateTargetVisibility();
    }

    public ShortcutBinding Binding { get; private set; }

    private void UpdateTargetVisibility()
    {
        var kind = kindCombo.SelectedItem as ShortcutActionKind? ?? ShortcutActionKind.None;
        var requiresTarget = Binding.RequiresTarget;
        targetLabel.Visible = requiresTarget;
        targetBox.Visible = requiresTarget;
        targetBox.PlaceholderText = GetTargetPlaceholder(kind);
    }

    private string GetTargetPlaceholder(ShortcutActionKind kind)
    {
        return kind switch
        {
            ShortcutActionKind.OpenApplication => "应用程序路径",
            ShortcutActionKind.OpenFolder => "文件夹路径",
            ShortcutActionKind.OpenWebsite => "网址",
            ShortcutActionKind.ImageQuickLook => "图片路径",
            _ => ""
        };
    }

    private void SaveAndClose()
    {
        Binding = new ShortcutBinding
        {
            Key = Binding.Key,
            Kind = kindCombo.SelectedItem as ShortcutActionKind? ?? ShortcutActionKind.None,
            Title = titleBox.Text,
            Target = targetBox.Text
        };
        DialogResult = DialogResult.OK;
        Close();
    }
}
