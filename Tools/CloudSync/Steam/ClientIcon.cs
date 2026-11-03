using SteamKit2;

namespace CloudSync.Steam;

static class ClientIcon
{
    /// The hash naming the app's Windows icon (`common.clienticon`), the
    /// multi-size `.ico` Steam puts on its own desktop shortcuts. Null when the
    /// app has none or the value isn't a SHA-1 hex string.
    public static string? Hash(KeyValue appInfo)
    {
        var value = appInfo["common"]["clienticon"].Value;
        if (value is null || value.Length != 40 || !value.All(Uri.IsHexDigit)) return null;
        return value.ToLowerInvariant();
    }
}
