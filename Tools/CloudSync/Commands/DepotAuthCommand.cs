using System.IO.Compression;
using System.IO.IsolatedStorage;
using System.Reflection;
using ProtoBuf;

namespace CloudSync.Commands;

/// `prepare-depot-auth`: bridges BEER's Keychain-owned refresh token into
/// DepotDownloader's own account cache for one invocation.
static class DepotAuthCommand
{
    public static string Prepare(string depotExecutable, string account, string token)
    {
        var configPath = DepotAuthConfigPath(depotExecutable);
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);

        var settings = new DepotAccountSettings();
        settings.LoginTokens[account] = token;

        var tempPath = $"{configPath}.{Guid.NewGuid():N}.tmp";
        try
        {
            using (var file = new FileStream(tempPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            using (var deflate = new DeflateStream(file, CompressionMode.Compress))
                Serializer.Serialize(deflate, settings);

            if (!OperatingSystem.IsWindows())
                File.SetUnixFileMode(tempPath, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            File.Move(tempPath, configPath, overwrite: true);
        }
        finally
        {
            if (File.Exists(tempPath)) File.Delete(tempPath);
        }
        return configPath;
    }

    static string DepotAuthConfigPath(string depotExecutable)
    {
        var isolatedRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "IsolatedStorage");
        Directory.CreateDirectory(isolatedRoot);

        var first = Directory.GetDirectories(isolatedRoot)
            .FirstOrDefault(path => Path.GetFileName(path).Length == 12);
        if (first == null)
        {
            first = Path.Combine(isolatedRoot, Path.GetRandomFileName());
            Directory.CreateDirectory(first);
        }
        var second = Directory.GetDirectories(first)
            .FirstOrDefault(path => Path.GetFileName(path).Length == 12);
        if (second == null)
        {
            second = Path.Combine(first, Path.GetRandomFileName());
            Directory.CreateDirectory(second);
        }

        var identityHelper = typeof(IsolatedStorageFile).Assembly
            .GetType("System.Security.IdentityHelper")
            ?? throw new Exception("Could not locate .NET isolated-storage identity support.");
        var hashMethod = identityHelper.GetMethod(
            "GetNormalizedUriHash", BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new Exception("Could not calculate DepotDownloader's isolated-storage identity.");
        var executableUri = new Uri(Path.GetFullPath(depotExecutable));
        var hash = hashMethod.Invoke(null, [executableUri]) as string
            ?? throw new Exception("Could not calculate DepotDownloader's isolated-storage path.");

        return Path.Combine(second, $"Url.{hash}", "AssemFiles", "account.config");
    }
}
