using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Fuguang.Windows;

internal sealed class GlobalHotKeyManager : IDisposable
{
    private const int WmHotKey = 0x0312;
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;
    private const int VkControl = 0x11;
    private const int VkLControl = 0xA2;
    private const int VkRControl = 0xA3;
    private const int VkMenu = 0x12;
    private const int VkLMenu = 0xA4;
    private const int VkRMenu = 0xA5;
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;

    private readonly Dictionary<int, string> hotKeyIds = [];
    private readonly LowLevelKeyboardProc keyboardProc;
    private int nextId = 100;
    private IntPtr windowHandle;
    private IntPtr keyboardHook;
    private bool modifierDown;
    private bool modifierAloneCandidate;
    private HotKeyModifier currentModifier = HotKeyModifier.Alt;

    public event EventHandler<string>? HotKeyPressed;
    public event EventHandler? ModifierPressedAlone;

    public GlobalHotKeyManager()
    {
        keyboardProc = KeyboardHookCallback;
        try
        {
            using var process = Process.GetCurrentProcess();
            using var module = process.MainModule;
            var moduleHandle = module?.ModuleName == null ? IntPtr.Zero : GetModuleHandle(module.ModuleName);
            keyboardHook = SetWindowsHookEx(WhKeyboardLl, keyboardProc, moduleHandle, 0);
        }
        catch
        {
            keyboardHook = IntPtr.Zero;
        }
    }

    public void RegisterAll(IntPtr handle, IEnumerable<ShortcutBinding> bindings, HotKeyModifier modifier)
    {
        windowHandle = handle;
        currentModifier = modifier;
        UnregisterAll();

        foreach (var binding in bindings)
        {
            if (!TryGetVirtualKey(binding.Key, out var virtualKey))
            {
                continue;
            }

            var id = nextId++;
            if (RegisterHotKey(windowHandle, id, ModifierFlag(modifier), virtualKey))
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
        if (keyboardHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(keyboardHook);
            keyboardHook = IntPtr.Zero;
        }
    }

    private IntPtr KeyboardHookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var message = wParam.ToInt32();
            var vkCode = Marshal.ReadInt32(lParam);
            var isModifier = currentModifier switch
            {
                HotKeyModifier.Ctrl => vkCode is VkControl or VkLControl or VkRControl,
                _ => vkCode is VkMenu or VkLMenu or VkRMenu
            };

            if (message is WmKeyDown or WmSysKeyDown)
            {
                if (isModifier)
                {
                    if (!modifierDown)
                    {
                        modifierAloneCandidate = true;
                    }

                    modifierDown = true;
                }
                else if (modifierDown)
                {
                    modifierAloneCandidate = false;
                }
            }
            else if (message is WmKeyUp or WmSysKeyUp)
            {
                if (isModifier)
                {
                    if (modifierDown && modifierAloneCandidate)
                    {
                        ModifierPressedAlone?.Invoke(this, EventArgs.Empty);
                    }

                    modifierDown = false;
                    modifierAloneCandidate = false;
                }
            }
        }

        return CallNextHookEx(keyboardHook, nCode, wParam, lParam);
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

    private static uint ModifierFlag(HotKeyModifier modifier) => modifier switch
    {
        HotKeyModifier.Ctrl => ModControl,
        _ => ModAlt
    };

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);
}
