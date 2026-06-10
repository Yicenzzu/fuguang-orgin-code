namespace Fuguang.Windows;

internal enum ShortcutActionKind
{
    None,
    OpenApplication,
    OpenFolder,
    OpenWebsite,
    ShowDesktop,
    Screenshot,
    ImageResize,
    ImageQuickLook,
    Clipboard,
    LockScreen
}

internal sealed class ShortcutBinding
{
    public string Key { get; set; } = "";
    public ShortcutActionKind Kind { get; set; } = ShortcutActionKind.None;
    public string Title { get; set; } = "";
    public string Target { get; set; } = "";

    public bool RequiresTarget => Kind is ShortcutActionKind.OpenApplication
        or ShortcutActionKind.OpenFolder
        or ShortcutActionKind.OpenWebsite
        or ShortcutActionKind.ImageQuickLook;

    public bool IsConfigured => Kind != ShortcutActionKind.None
        && (!RequiresTarget || !string.IsNullOrWhiteSpace(Target));

    public string DisplayTitle
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(Title))
            {
                return Title;
            }

            return Kind switch
            {
                ShortcutActionKind.None => "点击设置",
                ShortcutActionKind.OpenApplication or ShortcutActionKind.OpenFolder or ShortcutActionKind.ImageQuickLook
                    => Path.GetFileNameWithoutExtension(Target.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)),
                ShortcutActionKind.OpenWebsite => Target,
                _ => Kind.Title()
            };
        }
    }

    public static ShortcutBinding Empty(string key) => new() { Key = key };
}

internal static class ShortcutActionKindExtensions
{
    public static string Title(this ShortcutActionKind kind) => kind switch
    {
        ShortcutActionKind.None => "未设置",
        ShortcutActionKind.OpenApplication => "打开应用",
        ShortcutActionKind.OpenFolder => "打开文件夹",
        ShortcutActionKind.OpenWebsite => "打开网站",
        ShortcutActionKind.ShowDesktop => "浮光回桌",
        ShortcutActionKind.Screenshot => "浮光截图",
        ShortcutActionKind.ImageResize => "浮光改图",
        ShortcutActionKind.ImageQuickLook => "浮光图鉴",
        ShortcutActionKind.Clipboard => "浮光剪贴",
        ShortcutActionKind.LockScreen => "浮光锁屏",
        _ => kind.ToString()
    };
}

internal static class KeyboardLayout
{
    public static readonly string[][] Rows =
    [
        [.. "1234567890-=".Select(c => c.ToString())],
        [.. "QWERTYUIOP".Select(c => c.ToString())],
        [.. "ASDFGHJKL".Select(c => c.ToString())],
        [.. "ZXCVBNM".Select(c => c.ToString())]
    ];

    public static readonly IReadOnlyList<string> Keys = Rows.SelectMany(row => row).ToArray();
}
