using System.Runtime.InteropServices;

namespace Fuguang.Windows;

internal sealed class GlobalHotKeyManager : IDisposable
{
    private const int WmHotKey = 0x0312;
    private const uint ModControl = 0x0002;

    private readonly Dictionary<int, string> hotKeyIds = [];
    private int nextId = 100;
    private IntPtr windowHandle;

    public event EventHandler<string>? HotKeyPressed;

    public void RegisterAll(IntPtr handle, IEnumerable<ShortcutBinding> bindings)
    {
        windowHandle = handle;
        UnregisterAll();

        foreach (var binding in bindings)
        {
            if (!TryGetVirtualKey(binding.Key, out var virtualKey))
            {
                continue;
            }

            var id = nextId++;
            if (RegisterHotKey(windowHandle, id, ModControl, virtualKey))
            {
                hotKeyIds[id] = binding.Key;
            }
        }
    }

    public bool HandleMessage(ref Message message)
    {
        if (message.Msg != WmHotKey)
        {
            return false;
        }

        var id = message.WParam.ToInt32();
        if (!hotKeyIds.TryGetValue(id, out var key))
        {
            return false;
        }

        HotKeyPressed?.Invoke(this, key);
        return true;
    }

    public void UnregisterAll()
    {
        foreach (var id in hotKeyIds.Keys)
        {
            UnregisterHotKey(windowHandle, id);
        }

        hotKeyIds.Clear();
    }

    public void Dispose()
    {
        UnregisterAll();
    }

    private static bool TryGetVirtualKey(string key, out uint virtualKey)
    {
        virtualKey = key switch
        {
            "-" => 0xBD,
            "=" => 0xBB,
            _ when key.Length == 1 => char.ToUpperInvariant(key[0]),
            _ => 0
        };

        return virtualKey != 0;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
