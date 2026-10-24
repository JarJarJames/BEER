using System.Security.Cryptography;
using CloudSync.Steam;
using SteamKit2;
using SteamKit2.Internal;

namespace CloudSync.Transfers;

/// Single-file Steam Cloud download and upload over an existing logon.
static class CloudTransfers
{
    public static async Task DownloadAsync(SteamSession s, uint appid, string filename, string outPath)
    {
        using var http = NewHttpClient();
        await DownloadAsync(s, appid, filename, outPath, http);
    }

    public static async Task DownloadAsync(SteamSession s, uint appid, string filename, string outPath, HttpClient http)
    {
        var job = s.Cloud.ClientFileDownload(new CCloud_ClientFileDownload_Request
        {
            appid = appid,
            filename = filename,
            realm = 1,
        });
        var resp = await job;
        if (resp.Result != EResult.OK)
            throw new Exception($"ClientFileDownload failed: {resp.Result}");
        var body = resp.Body;
        if (body.is_explicit_delete)
            throw new Exception("Cloud reports this file as deleted.");
        if (body.encrypted)
            throw new Exception("Cloud returned an encrypted file; encrypted download is not supported.");

        var scheme = body.use_https ? "https" : "http";
        var url = $"{scheme}://{body.url_host}{body.url_path}";
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        foreach (var h in body.request_headers)
            req.Headers.TryAddWithoutValidation(h.name, h.value);

        using var httpResp = await http.SendAsync(req);
        httpResp.EnsureSuccessStatusCode();
        var bytes = await httpResp.Content.ReadAsByteArrayAsync();

        if (body.file_size != 0 && bytes.Length != body.file_size)
            Console.Error.WriteLine($"warning: downloaded {bytes.Length} bytes, expected {body.file_size}");

        bytes = CloudFileUnwrapper.Unwrap(bytes, body.file_size, body.raw_file_size, body.sha_file, filename);

        var dir = Path.GetDirectoryName(Path.GetFullPath(outPath));
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        await File.WriteAllBytesAsync(outPath, bytes);
        try { File.SetLastWriteTimeUtc(outPath, DateTimeOffset.FromUnixTimeSeconds((long)body.time_stamp).UtcDateTime); } catch { }
    }

    public static async Task UploadAsync(SteamSession s, uint appid, string filename, string inPath, long mtime)
    {
        using var http = NewHttpClient();
        await UploadAsync(s, appid, filename, inPath, mtime, http);
    }

    public static async Task UploadAsync(SteamSession s, uint appid, string filename, string inPath, long mtime, HttpClient http)
    {
        var data = await File.ReadAllBytesAsync(inPath);
        var sha1 = SHA1.HashData(data); // Steam keys cloud files by SHA1 of contents.

        var begin = await s.Cloud.ClientBeginFileUpload(new CCloud_ClientBeginFileUpload_Request
        {
            appid = appid,
            file_size = (uint)data.Length,
            raw_file_size = (uint)data.Length,
            file_sha = sha1,
            time_stamp = (ulong)mtime,
            filename = filename,
            can_encrypt = false,
            platforms_to_sync = 0xFFFFFFFF, // all platforms — so the Windows client sees it
        });
        if (begin.Result != EResult.OK)
            throw new Exception($"ClientBeginFileUpload failed: {begin.Result}");
        if (begin.Body.encrypt_file)
            throw new Exception("Steam requires an encrypted upload for this file; not supported. Aborting before any commit so nothing is corrupted.");

        foreach (var block in begin.Body.block_requests)
        {
            var scheme = block.use_https ? "https" : "http";
            var url = $"{scheme}://{block.url_host}{block.url_path}";
            var method = HttpMethodFor(block.http_method);

            byte[] payload = (block.explicit_body_data != null && block.explicit_body_data.Length > 0)
                ? block.explicit_body_data
                : data.Skip((int)block.block_offset).Take((int)block.block_length).ToArray();

            using var req = new HttpRequestMessage(method, url) { Content = new ByteArrayContent(payload) };
            foreach (var h in block.request_headers)
            {
                // Content-* headers must go on the content, not the request.
                if (h.name.StartsWith("Content-", StringComparison.OrdinalIgnoreCase))
                    req.Content.Headers.TryAddWithoutValidation(h.name, h.value);
                else
                    req.Headers.TryAddWithoutValidation(h.name, h.value);
            }

            using var blockResp = await http.SendAsync(req);
            if (!blockResp.IsSuccessStatusCode)
            {
                // Tell Steam the transfer failed so it doesn't leave a half-committed file.
                await CommitAsync(s, appid, sha1, filename, succeeded: false);
                throw new Exception($"Block upload failed: HTTP {(int)blockResp.StatusCode} {url}");
            }
        }

        var commit = await CommitAsync(s, appid, sha1, filename, succeeded: true);
        if (commit.Result != EResult.OK)
            throw new Exception($"ClientCommitFileUpload failed: {commit.Result}");
    }

    static async Task<SteamUnifiedMessages.ServiceMethodResponse<CCloud_ClientCommitFileUpload_Response>>
        CommitAsync(SteamSession s, uint appid, byte[] sha1, string filename, bool succeeded)
    {
        return await s.Cloud.ClientCommitFileUpload(new CCloud_ClientCommitFileUpload_Request
        {
            transfer_succeeded = succeeded,
            appid = appid,
            file_sha = sha1,
            filename = filename,
        });
    }

    internal static HttpMethod HttpMethodFor(int eHttpMethod) => eHttpMethod switch
    {
        // EHTTPMethod: 1=GET 2=HEAD 3=POST 4=PUT 5=DELETE ...
        3 => HttpMethod.Post,
        4 => HttpMethod.Put,
        _ => HttpMethod.Put, // cloud block uploads are PUT in practice
    };

    public static HttpClient NewHttpClient()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        c.DefaultRequestHeaders.UserAgent.ParseAdd("Valve/Steam HTTP Client 1.0");
        return c;
    }
}
