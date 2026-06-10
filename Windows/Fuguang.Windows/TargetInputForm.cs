namespace Fuguang.Windows;

internal sealed class TargetInputForm : Form
{
    private readonly TextBox nameBox = new();
    private readonly TextBox valueBox = new();

    public TargetInputForm(string title, string prompt, string initialValue, string initialName = "")
    {
        Text = title;
        Width = 420;
        Height = 250;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MaximizeBox = false;
        MinimizeBox = false;

        var okButton = new Button { Text = "保存" };
        var cancelButton = new Button { Text = "取消", DialogResult = DialogResult.Cancel };
        okButton.Click += (_, _) => SaveAndClose();

        AcceptButton = okButton;
        CancelButton = cancelButton;

        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(16),
            RowCount = 6,
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

        nameBox.Text = initialName ?? "";
        nameBox.Dock = DockStyle.Fill;
        nameBox.PlaceholderText = "显示名称，例如：百度";

        valueBox.Text = initialValue ?? "";
        valueBox.Dock = DockStyle.Fill;
        valueBox.PlaceholderText = "网址，例如：www.baidu.com";

        var nameLabel = new Label { Text = "名称", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft };
        layout.Controls.Add(nameLabel, 0, 0);
        layout.SetColumnSpan(nameLabel, 2);
        layout.Controls.Add(nameBox, 0, 1);
        layout.SetColumnSpan(nameBox, 2);

        var promptLabel = new Label { Text = prompt, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft };
        layout.Controls.Add(promptLabel, 0, 3);
        layout.SetColumnSpan(promptLabel, 2);
        layout.Controls.Add(valueBox, 0, 4);
        layout.SetColumnSpan(valueBox, 2);

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            Padding = new Padding(0, 10, 0, 0)
        };
        buttons.Controls.Add(okButton);
        buttons.Controls.Add(cancelButton);
        layout.Controls.Add(buttons, 0, 5);
        layout.SetColumnSpan(buttons, 2);

        Controls.Add(layout);
    }

    public string DisplayName { get; private set; } = "";

    public string Value { get; private set; } = "";

    private void SaveAndClose()
    {
        DisplayName = nameBox.Text.Trim();
        Value = valueBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(Value))
        {
            MessageBox.Show(this, "请先输入内容。", "Fuguang", MessageBoxButtons.OK, MessageBoxIcon.Information);
            valueBox.Focus();
            return;
        }

        if (string.IsNullOrWhiteSpace(DisplayName))
        {
            DisplayName = Value;
        }

        DialogResult = DialogResult.OK;
        Close();
    }
}
