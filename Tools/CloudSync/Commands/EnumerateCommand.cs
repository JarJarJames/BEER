using System.Text.Json;
using SteamKit2;
using SteamKit2.Internal;
using CloudSync.Cli;
using CloudSync.Steam;

namespace CloudSync.Commands;

/// `enumerate`: lists every Steam Cloud file for an app. One logon, read-only.
static class EnumerateCommand
{
    public static async Task RunAsync(SteamSession s, uint appid)
    {
        var files = new List<object>();
        uint startIndex = 0;
        int page = 0;
        while (true)
        {
            page++;
            Console.Error.WriteLine($"enumerate: requesting page {page} (start_index={startIndex})");
            var job = s.Cloud.EnumerateUserFiles(new CCloud_EnumerateUserFiles_Request
            {
                appid = appid,
                extended_details = true,
                count = 500,
                start_index = startIndex,
            });
            // A unified-message job that never completes must not hang this
            // command forever with nothing on stdout to explain why. AsyncJob
            // isn't itself a Task, so wrap it to race against a timeout.
            var respTask = Task.Run(async () => await job);
            var timeout = Task.Delay(TimeSpan.FromSeconds(30));
            if (await Task.WhenAny(respTask, timeout) == timeout)
                throw new Exception($"enumerate page {page}: timed out waiting for Steam's response");
            var resp = await respTask;
            Console.Error.WriteLine(
                $"enumerate: page {page} result={resp.Result} files={resp.Body?.files?.Count.ToString() ?? "null"} " +
                $"total_files={resp.Body?.total_files.ToString() ?? "null"}");
            if (resp.Result != EResult.OK)
                throw new Exception($"EnumerateUserFiles failed: {resp.Result}");
            var body = resp.Body ?? throw new Exception($"enumerate page {page}: Steam returned OK with no body");
            foreach (var f in body.files)
            {
                files.Add(new Dictionary<string, object?>
                {
                    ["filename"] = f.filename,
                    ["size"] = f.file_size,
                    ["timestamp"] = f.timestamp,
                    ["sha"] = f.file_sha,
                    ["ugcid"] = f.ugcid.ToString(),
                });
            }
            startIndex += (uint)body.files.Count;
            if (body.files.Count == 0 || startIndex >= body.total_files) break;
        }
        Console.Error.WriteLine($"enumerate: {files.Count} files total, serializing…");
        var json = JsonSerializer.Serialize(new Dictionary<string, object?> { ["files"] = files });
        Console.Error.WriteLine($"enumerate: serialized {json.Length} chars, writing…");
        JsonOutput.WriteLine(json);
        Console.Error.WriteLine("enumerate: emitted.");
    }
}
