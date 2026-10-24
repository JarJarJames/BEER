using System.Text.Json;
using CloudSync.Cli;
using CloudSync.Steam;
using CloudSync.Transfers;

namespace CloudSync.Commands;

static class BatchCommand
{
    // Process many downloads/uploads in ONE logged-on session. Spawning a fresh
    // process (= fresh Steam logon) per file gets the account throttled by the
    // CM after ~100 logons; batching keeps it to a single logon per sync. File
    // transfers are bounded so high-file-count games do not pay every Steam +
    // HTTP round trip serially, without flooding the service.
    public static async Task RunAsync(SteamSession s, uint appid, string jobsPath)
    {
        using var doc = JsonDocument.Parse(await File.ReadAllTextAsync(jobsPath));
        var root = doc.RootElement;
        int downloaded = 0, uploaded = 0, failed = 0;
        using var http = CloudTransfers.NewHttpClient();

        if (root.TryGetProperty("downloads", out var dls))
        {
            var jobs = dls.EnumerateArray()
                .Select(d => (
                    Filename: d.GetProperty("filename").GetString()!,
                    OutputPath: d.GetProperty("out").GetString()!))
                .ToList();
            await RunTransfersAsync(jobs, async d =>
            {
                try
                {
                    await CloudTransfers.DownloadAsync(s, appid, d.Filename, d.OutputPath, http);
                    Interlocked.Increment(ref downloaded);
                    JsonOutput.Emit(new Dictionary<string, object?> { ["op"] = "download", ["filename"] = d.Filename, ["ok"] = true });
                }
                catch (Exception ex)
                {
                    Interlocked.Increment(ref failed);
                    JsonOutput.Emit(new Dictionary<string, object?> { ["op"] = "download", ["filename"] = d.Filename, ["error"] = ex.Message });
                }
            });
        }

        if (root.TryGetProperty("uploads", out var uls))
        {
            var jobs = uls.EnumerateArray()
                .Select(u => (
                    Filename: u.GetProperty("filename").GetString()!,
                    InputPath: u.GetProperty("in").GetString()!,
                    MTime: u.GetProperty("mtime").GetInt64()))
                .ToList();
            await RunTransfersAsync(jobs, async u =>
            {
                try
                {
                    await CloudTransfers.UploadAsync(s, appid, u.Filename, u.InputPath, u.MTime, http);
                    Interlocked.Increment(ref uploaded);
                    JsonOutput.Emit(new Dictionary<string, object?> { ["op"] = "upload", ["filename"] = u.Filename, ["ok"] = true });
                }
                catch (Exception ex)
                {
                    Interlocked.Increment(ref failed);
                    JsonOutput.Emit(new Dictionary<string, object?> { ["op"] = "upload", ["filename"] = u.Filename, ["error"] = ex.Message });
                }
            });
        }

        JsonOutput.Emit(new Dictionary<string, object?> { ["summary"] = true, ["downloaded"] = downloaded, ["uploaded"] = uploaded, ["failed"] = failed });
    }

    const int MaxConcurrentTransfers = 4;

    static async Task RunTransfersAsync<T>(IEnumerable<T> jobs, Func<T, Task> transfer)
    {
        using var gate = new SemaphoreSlim(MaxConcurrentTransfers);
        var tasks = jobs.Select(async job =>
        {
            await gate.WaitAsync();
            try { await transfer(job); }
            finally { gate.Release(); }
        });
        await Task.WhenAll(tasks);
    }
}
