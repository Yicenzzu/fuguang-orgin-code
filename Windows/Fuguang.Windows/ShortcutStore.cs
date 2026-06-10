using System.Text.Json;
using System.Text.Json.Serialization;

namespace Fuguang.Windows;

internal sealed class ShortcutStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    private readonly string storagePath;
    private readonly Dictionary<string, ShortcutBinding> bindings = [];

    public ShortcutStore()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var directory = Path.Combine(appData, "Fuguang");
        storagePath = Path.Combine(directory, "bindings.windows.json");
        Load();
    }

    public event EventHandler? Changed;

    public ShortcutBinding BindingFor(string key)
    {
        return bindings.TryGetValue(key, out var binding) ? binding : ShortcutBinding.Empty(key);
    }

    public IReadOnlyList<ShortcutBinding> ConfiguredBindings()
    {
        return KeyboardLayout.Keys
            .Select(BindingFor)
            .Where(binding => binding.IsConfigured)
            .ToArray();
    }

    public void Save(ShortcutBinding binding)
    {
        bindings[binding.Key] = binding;
        Persist();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Clear(string key)
    {
        bindings[key] = ShortcutBinding.Empty(key);
        Persist();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    private void Load()
    {
        foreach (var key in KeyboardLayout.Keys)
        {
            bindings[key] = ShortcutBinding.Empty(key);
        }

        if (!File.Exists(storagePath))
        {
            return;
        }

        try
        {
            var json = File.ReadAllText(storagePath);
            var decoded = JsonSerializer.Deserialize<Dictionary<string, ShortcutBinding>>(json, JsonOptions);
            if (decoded == null)
            {
                return;
            }

            foreach (var (key, binding) in decoded)
            {
                if (KeyboardLayout.Keys.Contains(key))
                {
                    bindings[key] = binding;
                }
            }
        }
        catch
        {
            // A broken config file should not prevent the launcher from starting.
        }
    }

    private void Persist()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(storagePath)!);
        var json = JsonSerializer.Serialize(bindings, JsonOptions);
        File.WriteAllText(storagePath, json);
    }
}
