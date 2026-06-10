using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace Fuguang.Windows;

internal sealed class MainForm : Form
{
    private static readonly Icon AppIcon = LoadAppIcon();

    private static Icon LoadAppIcon()
    {
        var assembly = typeof(MainForm).Assembly;
        var resourceName = assembly.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith("Fuguang.ico", StringComparison.OrdinalIgnoreCase));
        if (resourceName != null)
        {
            using var stream = assembly.GetManifestResourceStream(resourceName);
            if (stream != null) return new Icon(stream);
        }
        return SystemIcons.Application;
    }

    private const int CornerRadius = 28;
    private const int BaseWidth = 1560;
    private const int BaseHeight = 840;

    private readonly ShortcutStore store = new();
    private readonly GlobalHotKeyManager hotKeys = new();
    private readonly Dictionary<string, KeyTile> keyTiles = [];
    private readonly Dictionary<string, Image> iconCache = [];
    private readonly NotifyIcon trayIcon;
    private readonly ToolTip toolTip = new();
    private ContextMenuStrip? activeBindingMenu;

    public MainForm()
    {
        Text = "Fuguang";
        ApplyResponsiveWindowSize();
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.None;
        BackColor = Color.FromArgb(244, 249, 255);
        Opacity = 1.0;
        DoubleBuffered = true;

        trayIcon = new NotifyIcon
        {
            Icon = AppIcon,
            Text = "Fuguang",
            Visible = true,
            ContextMenuStrip = BuildTrayMenu()
        };
        trayIcon.DoubleClick += (_, _) => ShowMainWindow();

        Controls.Add(BuildSurface());

        store.Changed += (_, _) =>
        {
            RefreshTiles();
            RegisterHotKeys();
        };
        hotKeys.HotKeyPressed += (_, key) => RunKey(key);
        hotKeys.ModifierPressedAlone += (_, _) => BeginInvoke((Action)ShowMainWindow);

        Shown += (_, _) => RegisterHotKeys();
        FormClosing += OnFormClosing;
        Resize += (_, _) =>
        {
            ApplyResponsiveTileMetrics();
            UpdateWindowRegion();
            if (WindowState == FormWindowState.Minimized)
            {
                Hide();
            }
        };

        UpdateWindowRegion();
        ApplyResponsiveTileMetrics();
        RefreshTiles();
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        if (ClientSize.Width <= 0 || ClientSize.Height <= 0)
        {
            using var fallbackBrush = new SolidBrush(Color.FromArgb(244, 249, 255));
            e.Graphics.FillRectangle(fallbackBrush, ClientRectangle);
            return;
        }

        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

        using var brush = new LinearGradientBrush(
            ClientRectangle,
            Color.FromArgb(252, 254, 255),
            Color.FromArgb(214, 234, 255),
            35f);
        e.Graphics.FillRectangle(brush, ClientRectangle);

        using var washBrush = new SolidBrush(Color.FromArgb(105, 236, 247, 255));
        e.Graphics.FillEllipse(washBrush, -Width / 6, Height / 5, Width / 2, Height / 2);

        using var blueBrush = new SolidBrush(Color.FromArgb(82, 152, 196, 248));
        e.Graphics.FillEllipse(blueBrush, Width - Width / 3, -Height / 5, Width / 2, Height / 2);
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        // Keep the main surface opaque white for maximum contrast.
    }

    protected override void WndProc(ref Message message)
    {
        if (hotKeys.HandleMessage(ref message))
        {
            return;
        }

        base.WndProc(ref message);
    }

    private Control BuildSurface()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(48, 28, 48, 18),
            BackColor = Color.Transparent,
            RowCount = 2,
            ColumnCount = 1
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 150));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        root.Controls.Add(BuildTitleBar(), 0, 0);
        root.Controls.Add(BuildKeyboardPanel(), 0, 1);
        return root;
    }

    private Control BuildTitleBar()
    {
        var panel = new Panel
        {
            Dock = DockStyle.Fill,
            BackColor = Color.Transparent
        };
        panel.MouseDown += (_, e) => BeginDrag(e);

        var brand = new VerticalBrandLabel
        {
            BrandText = "浮光",
            Font = new Font(Font.FontFamily, 25, FontStyle.Bold, GraphicsUnit.Point),
            Location = new Point(18, 10),
            Size = new Size(96, 120)
        };
        brand.MouseDown += (_, e) => BeginDrag(e);

        var slogan = new Label
        {
            AutoSize = false,
            Text = "让常用的一切，一键触达",
            ForeColor = Color.FromArgb(76, 92, 112),
            Font = new Font(Font.FontFamily, 14, FontStyle.Bold, GraphicsUnit.Point),
            Location = new Point(128, 50),
            Size = new Size(390, 44),
            TextAlign = ContentAlignment.MiddleLeft
        };
        slogan.MouseDown += (_, e) => BeginDrag(e);

        var closeButton = new Label
        {
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            Text = "×",
            Size = new Size(62, 62),
            Location = new Point(Width - 102, 16),
            ForeColor = Color.Black,
            BackColor = Color.Transparent,
            Font = new Font(Font.FontFamily, 22, FontStyle.Bold),
            TextAlign = ContentAlignment.MiddleCenter,
            Cursor = Cursors.Hand
        };
        closeButton.Click += (_, _) => Hide();
        panel.Resize += (_, _) => closeButton.Left = panel.Width - closeButton.Width - 8;

        panel.Controls.Add(brand);
        panel.Controls.Add(slogan);
        panel.Controls.Add(closeButton);
        return panel;
    }

    private Control BuildKeyboardPanel()
    {
        var board = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoSize = false,
            BackColor = Color.Transparent,
            RowCount = KeyboardLayout.Rows.Length,
            ColumnCount = 1
        };
        for (var i = 0; i < KeyboardLayout.Rows.Length; i++)
        {
            board.RowStyles.Add(new RowStyle(SizeType.Percent, 100f / KeyboardLayout.Rows.Length));
        }

        for (var rowIndex = 0; rowIndex < KeyboardLayout.Rows.Length; rowIndex++)
        {
            var panel = new FlowLayoutPanel
            {
                Anchor = AnchorStyles.None,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                BackColor = Color.Transparent,
                FlowDirection = FlowDirection.LeftToRight,
                WrapContents = false,
                Margin = new Padding(0, 5, 0, 5),
                Padding = Padding.Empty
            };

            foreach (var key in KeyboardLayout.Rows[rowIndex])
            {
                var tile = new KeyTile
                {
                    KeyName = key,
                    Width = 99,
                    Height = 90,
                    Margin = new Padding(9),
                    TabStop = true
                };
                tile.Click += (_, _) => ShowBindingMenu(tile, key);
                keyTiles[key] = tile;
                panel.Controls.Add(tile);
            }

            board.Controls.Add(panel, 0, rowIndex);
        }

        return board;
    }

    private ContextMenuStrip BuildTrayMenu()
    {
        var menu = new ContextMenuStrip
        {
            Renderer = new FuguangMenuRenderer(),
            BackColor = Color.White,
            ForeColor = Color.Black
        };
        menu.Items.Add("打开 Fuguang", null, (_, _) => ShowMainWindow());
        menu.Items.Add("退出", null, (_, _) =>
        {
            trayIcon.Visible = false;
            Application.Exit();
        });
        return menu;
    }

    private void RefreshTiles()
    {
        foreach (var (key, tile) in keyTiles)
        {
            var binding = store.BindingFor(key);
            tile.Binding = binding;
            tile.AccentColor = AccentFor(binding);
            tile.IconImage = binding.IsConfigured ? IconFor(binding) : null;
            toolTip.SetToolTip(tile, binding.IsConfigured
                ? $"{key}: {binding.DisplayTitle}\nCtrl + {key} 触发"
                : $"{key}: 点击设置动作");
        }
    }

    private void ShowBindingMenu(Control anchor, string key)
    {
        activeBindingMenu?.Dispose();
        var menu = BuildBindingMenu(key);
        activeBindingMenu = menu;
        menu.Closed += (_, _) =>
        {
            if (ReferenceEquals(activeBindingMenu, menu))
            {
                activeBindingMenu = null;
            }

            BeginInvoke(() =>
            {
                if (!menu.IsDisposed)
                {
                    menu.Dispose();
                }
            });
        };
        menu.Show(anchor, new Point(10, anchor.Height - 2));
    }

    private ContextMenuStrip BuildBindingMenu(string key)
    {
        var menu = new ContextMenuStrip
        {
            ShowImageMargin = true,
            Renderer = new FuguangMenuRenderer(),
            BackColor = Color.White,
            ForeColor = Color.Black,
            Padding = new Padding(8, 8, 8, 8)
        };

        menu.Items.Add(MenuItem("应用", ShortcutActionKind.OpenApplication, (_, _) => RunAfterMenuClose(() => BindApplication(key))));
        menu.Items.Add(MenuItem("文件夹", ShortcutActionKind.OpenFolder, (_, _) => RunAfterMenuClose(() => BindFolder(key))));
        menu.Items.Add(MenuItem("网页", ShortcutActionKind.OpenWebsite, (_, _) => RunAfterMenuClose(() => BindWebsite(key))));

        var actions = MenuItem("浮光操作", ShortcutActionKind.ShowDesktop, null);
        actions.DropDown.BackColor = Color.White;
        actions.DropDown.ForeColor = Color.Black;
        actions.DropDown.Renderer = new FuguangMenuRenderer();
        if (actions.DropDown is ToolStripDropDownMenu actionMenu)
        {
            actionMenu.ShowImageMargin = true;
        }

        actions.DropDownItems.Add(MenuItem("浮光截图", ShortcutActionKind.Screenshot, (_, _) => RunAfterMenuClose(() => BindBuiltIn(key, ShortcutActionKind.Screenshot))));
        actions.DropDownItems.Add(MenuItem("浮光剪贴", ShortcutActionKind.Clipboard, (_, _) => RunAfterMenuClose(() => BindBuiltIn(key, ShortcutActionKind.Clipboard))));
        actions.DropDownItems.Add(MenuItem("浮光回桌", ShortcutActionKind.ShowDesktop, (_, _) => RunAfterMenuClose(() => BindBuiltIn(key, ShortcutActionKind.ShowDesktop))));
        actions.DropDownItems.Add(MenuItem("浮光改图", ShortcutActionKind.ImageResize, (_, _) => RunAfterMenuClose(() => BindBuiltIn(key, ShortcutActionKind.ImageResize))));
        actions.DropDownItems.Add(MenuItem("浮光锁屏", ShortcutActionKind.LockScreen, (_, _) => RunAfterMenuClose(() => BindBuiltIn(key, ShortcutActionKind.LockScreen))));
        actions.DropDownItems.Add(MenuItem("图片预览...", ShortcutActionKind.ImageQuickLook, (_, _) => RunAfterMenuClose(() => BindImageQuickLook(key))));
        menu.Items.Add(actions);

        if (store.BindingFor(key).IsConfigured)
        {
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(MenuItem("编辑详情...", null, (_, _) => RunAfterMenuClose(() => EditBindingDialog(key))));
            menu.Items.Add(MenuItem("清除绑定", null, (_, _) => RunAfterMenuClose(() => store.Clear(key))));
        }

        return menu;
    }

    private void RunAfterMenuClose(Action action)
    {
        BeginInvoke(action);
    }

    private static ToolStripMenuItem MenuItem(string text, ShortcutActionKind? iconKind, EventHandler? onClick)
    {
        var item = new ToolStripMenuItem(text)
        {
            AutoSize = false,
            Height = 34,
            Width = 188,
            Font = new Font(FontFamily.GenericSansSerif, 10, FontStyle.Bold),
            ForeColor = Color.Black,
            BackColor = Color.White,
            Image = iconKind == null ? null : AppIcon.ToBitmap(),
            ImageScaling = ToolStripItemImageScaling.SizeToFit
        };

        if (onClick != null)
        {
            item.Click += onClick;
        }

        return item;
    }

    private void BindApplication(string key)
    {
        using var picker = new ApplicationPickerForm();
        if (picker.ShowDialog(this) != DialogResult.OK || picker.SelectedApp == null)
        {
            return;
        }

        store.Save(new ShortcutBinding
        {
            Key = key,
            Kind = ShortcutActionKind.OpenApplication,
            Target = picker.SelectedApp.TargetPath,
            Title = picker.SelectedApp.Name
        });
    }

    private void BindFolder(string key)
    {
        using var dialog = new FolderBrowserDialog();
        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            SaveBinding(key, ShortcutActionKind.OpenFolder, dialog.SelectedPath);
        }
    }

    private void BindWebsite(string key)
    {
        var binding = store.BindingFor(key);
        using var input = new TargetInputForm("网页", "网址", binding.Target, binding.Title);
        if (input.ShowDialog(this) == DialogResult.OK)
        {
            store.Save(new ShortcutBinding
            {
                Key = key,
                Kind = ShortcutActionKind.OpenWebsite,
                Target = input.Value,
                Title = input.DisplayName
            });
        }
    }

    private void BindImageQuickLook(string key)
    {
        using var dialog = new OpenFileDialog
        {
            Filter = "图片文件|*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.webp|所有文件 (*.*)|*.*",
            CheckFileExists = true,
            RestoreDirectory = true
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            SaveBinding(key, ShortcutActionKind.ImageQuickLook, dialog.FileName);
        }
    }

    private void BindBuiltIn(string key, ShortcutActionKind kind)
    {
        SaveBinding(key, kind, "");
    }

    private void SaveBinding(string key, ShortcutActionKind kind, string target)
    {
        store.Save(new ShortcutBinding
        {
            Key = key,
            Kind = kind,
            Target = target,
            Title = ""
        });
    }

    private void EditBindingDialog(string key)
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
            hotKeys.RegisterAll(Handle, store.ConfiguredBindings(), HotKeyModifier.Ctrl);
        }
    }

    private void ShowMainWindow()
    {
        ApplyResponsiveWindowSize();
        ApplyResponsiveTileMetrics();
        CenterToWorkingArea();
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
        toolTip.Dispose();
        activeBindingMenu?.Dispose();
        foreach (var image in iconCache.Values)
        {
            image.Dispose();
        }
    }

    private void UpdateWindowRegion()
    {
        if (ClientSize.Width <= 0 || ClientSize.Height <= 0)
        {
            return;
        }

        using var path = RoundedRectangle(ClientRectangle, CornerRadius);
        Region?.Dispose();
        Region = new Region(path);
    }

    private void ApplyResponsiveWindowSize()
    {
        var screen = Screen.FromPoint(Cursor.Position).WorkingArea;
        if (screen.Width <= 0 || screen.Height <= 0)
        {
            screen = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, BaseWidth, BaseHeight);
        }

        var maxWidth = Math.Max(720, Math.Min(BaseWidth, screen.Width - 40));
        var maxHeight = Math.Max(480, Math.Min(BaseHeight, screen.Height - 40));
        var minWidth = Math.Min(900, maxWidth);
        var minHeight = Math.Min(560, maxHeight);
        var width = Math.Clamp((int)(screen.Width * 0.82), minWidth, maxWidth);
        var height = Math.Clamp((int)(screen.Height * 0.74), minHeight, maxHeight);
        MinimumSize = new Size(Math.Min(780, width), Math.Min(480, height));
        Size = new Size(width, height);
    }

    private void ApplyResponsiveTileMetrics()
    {
        if (keyTiles.Count == 0 || ClientSize.Width <= 0 || ClientSize.Height <= 0)
        {
            return;
        }

        var availableWidth = Math.Max(520, ClientSize.Width - 160);
        var availableHeight = Math.Max(270, ClientSize.Height - 220);
        var widthByRow = (availableWidth - 12 * 18) / 12;
        var heightByRows = (availableHeight - 4 * 18) / 4;
        var tileWidth = Math.Clamp(Math.Min(widthByRow, (int)(heightByRows * 1.08)), 46, 72);
        tileWidth = Math.Clamp((int)(tileWidth * 1.30), 58, 92);
        var tileHeight = Math.Clamp((int)(tileWidth * 0.90), 52, 82);
        var margin = Math.Clamp(tileWidth / 13, 5, 8);

        foreach (var tile in keyTiles.Values)
        {
            tile.Width = tileWidth;
            tile.Height = tileHeight;
            tile.Margin = new Padding(margin);
        }
    }

    private void CenterToWorkingArea()
    {
        var screen = Screen.FromPoint(Cursor.Position).WorkingArea;
        Left = screen.Left + (screen.Width - Width) / 2;
        Top = screen.Top + (screen.Height - Height) / 2;
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

    private static Color AccentFor(ShortcutBinding binding)
    {
        if (!binding.IsConfigured)
        {
            return Color.FromArgb(42, 60, 79, 92);
        }

        return binding.Kind switch
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
    }

    private Image IconFor(ShortcutBinding binding)
    {
        var cacheKey = $"{binding.Kind}|{binding.Target}|{binding.Title}";
        if (!iconCache.TryGetValue(cacheKey, out var image))
        {
            image = ShortcutIconProvider.CreateIcon(binding);
            iconCache[cacheKey] = image;
        }

        return image;
    }

    private void BeginDrag(MouseEventArgs eventArgs)
    {
        if (eventArgs.Button != MouseButtons.Left)
        {
            return;
        }

        ReleaseCapture();
        SendMessage(Handle, 0xA1, 0x2, 0);
    }

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern int SendMessage(IntPtr hWnd, int msg, int wParam, int lParam);

    private void EnableBlurBehind()
    {
        try
        {
            var accent = new AccentPolicy
            {
                AccentState = 3,
                GradientColor = 0
            };
            var accentSize = Marshal.SizeOf<AccentPolicy>();
            var accentPtr = Marshal.AllocHGlobal(accentSize);
            try
            {
                Marshal.StructureToPtr(accent, accentPtr, false);
                var data = new WindowCompositionAttributeData
                {
                    Attribute = 19,
                    SizeOfData = accentSize,
                    Data = accentPtr
                };
                SetWindowCompositionAttribute(Handle, ref data);
            }
            finally
            {
                Marshal.FreeHGlobal(accentPtr);
            }
        }
        catch
        {
            // Blur is best-effort; keep the solid translucent background when unavailable.
        }
    }

    [DllImport("user32.dll")]
    private static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WindowCompositionAttributeData data);

    [StructLayout(LayoutKind.Sequential)]
    private struct AccentPolicy
    {
        public int AccentState;
        public int AccentFlags;
        public int GradientColor;
        public int AnimationId;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WindowCompositionAttributeData
    {
        public int Attribute;
        public IntPtr Data;
        public int SizeOfData;
    }
}
