namespace Fuguang.Windows;

internal sealed class ApplicationPickerForm : Form
{
    private readonly TextBox searchBox = new();
    private readonly ListView appList = new();
    private readonly ImageList icons = new() { ColorDepth = ColorDepth.Depth32Bit, ImageSize = new Size(28, 28) };
    private readonly List<AppEntry> allApps;

    public ApplicationPickerForm()
    {
        Text = "绑定应用";
        Width = 520;
        Height = 620;
        MinimumSize = new Size(420, 420);
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        BackColor = Color.White;
        ForeColor = Color.Black;

        allApps = AppEntry.LoadInstalledApps();
        allApps.Insert(0, new AppEntry("浏览其它应用...", ""));

        Controls.Add(BuildLayout());
        Load += (_, _) =>
        {
            PopulateList();
            searchBox.Focus();
        };
    }

    public AppEntry? SelectedApp { get; private set; }

    private Control BuildLayout()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(18),
            RowCount = 2,
            ColumnCount = 1,
            BackColor = Color.White
        };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        searchBox.Dock = DockStyle.Fill;
        searchBox.PlaceholderText = "搜索应用";
        searchBox.Font = new Font(FontFamily.GenericSansSerif, 11, FontStyle.Bold);
        searchBox.BackColor = Color.White;
        searchBox.ForeColor = Color.Black;
        searchBox.BorderStyle = BorderStyle.FixedSingle;
        searchBox.TextChanged += (_, _) => PopulateList();

        appList.Dock = DockStyle.Fill;
        appList.View = View.Details;
        appList.HeaderStyle = ColumnHeaderStyle.None;
        appList.FullRowSelect = true;
        appList.MultiSelect = false;
        appList.HideSelection = false;
        appList.BackColor = Color.White;
        appList.ForeColor = Color.Black;
        appList.BorderStyle = BorderStyle.FixedSingle;
        appList.Font = new Font(FontFamily.GenericSansSerif, 11, FontStyle.Bold);
        appList.SmallImageList = icons;
        appList.Columns.Add("应用", 440);
        appList.DoubleClick += (_, _) => AcceptSelection();
        appList.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Enter)
            {
                AcceptSelection();
            }
        };

        root.Controls.Add(searchBox, 0, 0);
        root.Controls.Add(appList, 0, 1);
        return root;
    }

    private void PopulateList()
    {
        var query = searchBox.Text.Trim();
        appList.BeginUpdate();
        appList.Items.Clear();
        icons.Images.Clear();

        var apps = allApps
            .Where(app => string.IsNullOrWhiteSpace(query)
                || app.Name.Contains(query, StringComparison.CurrentCultureIgnoreCase))
            .Take(200)
            .ToArray();

        for (var i = 0; i < apps.Length; i++)
        {
            icons.Images.Add(apps[i].LoadIcon());
            var item = new ListViewItem(apps[i].Name, i)
            {
                Tag = apps[i]
            };
            appList.Items.Add(item);
        }

        if (appList.Items.Count > 0)
        {
            appList.Items[0].Selected = true;
        }

        appList.EndUpdate();
    }

    private void AcceptSelection()
    {
        if (appList.SelectedItems.Count == 0)
        {
            return;
        }

        SelectedApp = (AppEntry)appList.SelectedItems[0].Tag!;
        if (string.IsNullOrWhiteSpace(SelectedApp.TargetPath))
        {
            using var dialog = new OpenFileDialog
            {
                Filter = "应用 (*.exe;*.lnk;*.appref-ms)|*.exe;*.lnk;*.appref-ms|所有文件 (*.*)|*.*",
                CheckFileExists = true,
                RestoreDirectory = true
            };

            if (dialog.ShowDialog(this) != DialogResult.OK)
            {
                SelectedApp = null;
                return;
            }

            SelectedApp = new AppEntry(Path.GetFileNameWithoutExtension(dialog.FileName), dialog.FileName);
        }

        DialogResult = DialogResult.OK;
        Close();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            icons.Dispose();
        }

        base.Dispose(disposing);
    }
}

internal sealed record AppEntry(string Name, string TargetPath)
{
    public static List<AppEntry> LoadInstalledApps()
    {
        var folders = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.StartMenu), "Programs"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu), "Programs")
        };

        return folders
            .Where(Directory.Exists)
            .SelectMany(folder => Directory.EnumerateFiles(folder, "*.*", SearchOption.AllDirectories))
            .Where(IsAppFile)
            .Select(path => new AppEntry(Path.GetFileNameWithoutExtension(path), path))
            .GroupBy(app => app.Name, StringComparer.CurrentCultureIgnoreCase)
            .Select(group => group.OrderBy(app => app.TargetPath.Length).First())
            .OrderBy(app => app.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    public Icon LoadIcon()
    {
        if (string.IsNullOrWhiteSpace(TargetPath))
        {
            return SystemIcons.WinLogo;
        }

        try
        {
            return Icon.ExtractAssociatedIcon(TargetPath) ?? SystemIcons.Application;
        }
        catch
        {
            return SystemIcons.Application;
        }
    }

    private static bool IsAppFile(string path)
    {
        var extension = Path.GetExtension(path);
        return extension.Equals(".lnk", StringComparison.OrdinalIgnoreCase)
            || extension.Equals(".exe", StringComparison.OrdinalIgnoreCase)
            || extension.Equals(".appref-ms", StringComparison.OrdinalIgnoreCase);
    }
}
