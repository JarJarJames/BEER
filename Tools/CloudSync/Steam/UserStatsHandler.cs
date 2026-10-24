using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading.Tasks;
using SteamKit2;
using SteamKit2.Internal;

/// Raw client-protocol handler for real Steam achievement/stat state.
///
/// SteamKit2 3.4.0's own `SteamUserStats` handler only wraps leaderboards and
/// current-player-count — it never claims `ClientGetUserStatsResponse` or
/// `ClientStoreUserStatsResponse` — so this handler exists purely to send
/// `ClientGetUserStats`/`ClientStoreUserStats2` and correlate the matching
/// response by JobID, the same low-level mechanism SteamKit2's own handlers
/// use internally for every `AsyncJob`-style call.
sealed class UserStatsHandler : ClientMsgHandler
{
    readonly ConcurrentDictionary<ulong, TaskCompletionSource<IPacketMsg>> _pending = new();

    public override void HandleMsg(IPacketMsg packetMsg)
    {
        switch (packetMsg.MsgType)
        {
            case EMsg.ClientGetUserStatsResponse:
            case EMsg.ClientStoreUserStatsResponse:
                if (_pending.TryRemove(packetMsg.TargetJobID, out var tcs))
                    tcs.TrySetResult(packetMsg);
                break;
        }
    }

    /// Real achievement/stat schema + current unlock state for `appId`, read
    /// straight from Steam over the client protocol — the same one cloud
    /// saves already use, not the Publisher-key-gated Web API.
    public async Task<CMsgClientGetUserStatsResponse> GetUserStatsAsync(uint appId, ulong steamId, TimeSpan timeout)
    {
        var msg = new ClientMsgProtobuf<CMsgClientGetUserStats>(EMsg.ClientGetUserStats)
        {
            SourceJobID = Client.GetNextJobID(),
        };
        msg.Body.game_id = appId;
        msg.Body.steam_id_for_user = steamId;
        msg.Body.schema_local_version = 0; // 0 = always send the full current schema back

        var packet = await SendAndAwait(msg, msg.SourceJobID, timeout);
        var resp = new ClientMsgProtobuf<CMsgClientGetUserStatsResponse>(packet);
        if ((EResult)resp.Body.eresult != EResult.OK)
            throw new Exception($"GetUserStats failed: {(EResult)resp.Body.eresult}");
        return resp.Body;
    }

    /// Push a full set of achievement-block bitmasks back to Steam. This is
    /// the write side of the pair, and unlike the read side it is NOT a
    /// well-trodden path — SteamKit2 never wraps it, and there's no known
    /// working precedent for calling it outside a real running
    /// game+steam_api+Steam client. It mirrors what GameNative's Android
    /// build does over JavaSteam's equivalent of this same protocol, so it
    /// should behave the same way here, but this is the one part of
    /// achievements support that genuinely needs live-account verification.
    public async Task<CMsgClientStoreUserStatsResponse> StoreUserStatsAsync(
        uint appId, ulong steamId, uint crcStats,
        List<(uint StatId, uint Value)> stats, TimeSpan timeout)
    {
        var msg = new ClientMsgProtobuf<CMsgClientStoreUserStats2>(EMsg.ClientStoreUserStats2)
        {
            SourceJobID = Client.GetNextJobID(),
        };
        msg.Body.game_id = appId;
        msg.Body.settor_steam_id = steamId;
        msg.Body.settee_steam_id = steamId;
        msg.Body.crc_stats = crcStats;
        msg.Body.explicit_reset = false;
        foreach (var (statId, value) in stats)
            msg.Body.stats.Add(new CMsgClientStoreUserStats2.Stats { stat_id = statId, stat_value = value });

        var packet = await SendAndAwait(msg, msg.SourceJobID, timeout);
        return new ClientMsgProtobuf<CMsgClientStoreUserStatsResponse>(packet).Body;
    }

    async Task<IPacketMsg> SendAndAwait(IClientMsg msg, ulong jobId, TimeSpan timeout)
    {
        var tcs = new TaskCompletionSource<IPacketMsg>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pending[jobId] = tcs;
        Client.Send(msg);

        var winner = await Task.WhenAny(tcs.Task, Task.Delay(timeout));
        if (winner != tcs.Task)
        {
            _pending.TryRemove(jobId, out _);
            throw new Exception("Timed out waiting for Steam's user-stats response.");
        }
        return await tcs.Task;
    }
}
