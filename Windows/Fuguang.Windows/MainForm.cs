namespace Fuguang.Windows;

internal sealed class MainForm : Form
{
    private readonly ShortcutStore store = new();
    private readonly GlobalHotKeyManager hotKeys = new();
    private readonly Dictionary<string, Button> keyButtons = [];
    private readonly NotifyIcon trayIcon;

    public MainForm()
    {
        Text = "Fuguang";
        Width = 980;
        Height = 460;
        MinimumSize = new Size(760, 360);
        StartPosition = FormStartPosition.CenterScreen;

        trayIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "Fuguang",
            Visible = true,
            ContextMenuStrip = BuildTrayMenu()
        };
        trayIcon.DoubleClick += (_, _) => ShowMainWindow();

        Controls.Add(BuildKeyboardPanel());

        store.Changed += (_, _) =>
        {
            RefreshButtons();
            RegisterHotKeys();
        };
        hotKeys.HotKeyPressed += (_, key) => RunKey(key);

        Shown += (_, _) => RegisterHotKeys();
        FormClosing += OnFormClosing;
        Resize += (_, _) =>
        {
            if (WindowState == FormWindowState.Minimized)
            {
                Hide();
            }
        };

        RefreshButtons();
    }

    protected override void WndProc(ref Message message)
    {
        if (hotKeys.HandleMessage(ref message))
        {
            return;
        }

        base.WndProc(ref message);
    }

    private ContextMenuStrip BuildTrayMenu()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("打开 Fuguang", null, (_, _) => ShowMainWindow());
        menu.Items.Add("退出", null, (_, _) =>
        {
            trayIcon.Visible = false;
            Application.Exit();
        });
        return menu;
    }

    private Control BuildKeyboardPanel()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(24),
            RowCount = KeyboardLayout.Rows.Length + 1,
            ColumnCount = 1
        };

        var hint = new Label
        {
            Text = "点击键帽设置动作。已配置键位可通过 Ctrl + 对应按键触发。",
            Dock = DockStyle.Fill,
            AutoSize = false,
            TextAlign = ContentAlignment.MiddleLeft,
            Font = new Font(Font.FontFamily, 11)
        };
        root.Controls.Add(hint);

        foreach (var row in KeyboardLayout.Rows)
        {
            var panel = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
                Padding = new Padding(0, 8, 0, 0)
            };

            foreach (var key in row)
            {
                var button = new Button
                {
                    Width = 78,
                    Height = 64,
                    Margin = new Padding(4),
                    Tag = key
                };
                button.Click += (_, _) => EditBinding(key);
                keyButtons[key] = button;
                panel.Controls.Add(button);
            }

            root.Controls.Add(panel);
        }

        return root;
    }

    private void RefreshButtons()
    {
        foreach (var (key, button) in keyButtons)
        {
            var binding = store.BindingFor(key);
            button.Text = binding.IsConfigured
                ? $"{key}{Environment.NewLine}{binding.DisplayTitle}"
                : $"{key}{Environment.NewLine}点击设置";
        }
    }

    private void EditBinding(string key)
    {
        using var editor = new BindingEditorForm(store.BindingFor(key));
        var result = editor.ShowDialog(this);
        if (result != DialogResult.OK)
        {
            return;
        }

        if (editor.Binding.Kind == ShortcutActionKind.None)
        {
            store.Clear(key);
            return;
        }

        store.Save(editor.Binding);
    }

    private void RunKey(string key)
    {
        ActionRunner.Run(store.BindingFor(key), this);
        Hide();
    }

    private void RegisterHotKeys()
    {
        if (IsHandleCreated)
        {
            hotKeys.RegisterAll(Handle, store.ConfiguredBindings());
        }
    }

    private void ShowMainWindow()
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs eventArgs)
    {
        if (eventArgs.CloseReason == CloseReason.UserClosing)
        {
            eventArgs.Cancel = true;
            Hide();
            return;
        }

        hotKeys.Dispose();
        trayIcon.Dispose();
    }
}
