using CloudSync.Cli;
using CloudSync.Steam;

namespace CloudSync.Commands.Presence;

sealed partial class PresenceSession
{
    async Task KeepaliveAsync(CancellationToken token)
    {
        var attempts = 0;
        var ticks = 0;
        var lastPump = -1L;
        while (!token.IsCancellationRequested)
        {
            try { await Task.Delay(TimeSpan.FromSeconds(5), token); }
            catch (OperationCanceledException) { break; }

            // A pump that stops advancing has stopped delivering callbacks,
            // and every symptom of that is silent: the socket reconnects,
            // the process stays alive, and nothing Steam sends is ever
            // acted on again. Fail loudly instead of flapping for hours.
            if (SteamSession.PumpIterations == lastPump)
            {
                JsonOutput.Emit(new Dictionary<string, object?>
                {
                    ["error"] = "The Steam callback pump stopped responding, so status and play time can't be tracked. Restarting BEER should clear it.",
                    ["fatal"] = true,
                });
                Environment.Exit(1);
            }
            lastPump = SteamSession.PumpIterations;

            Console.Error.WriteLine(
                $"tick: connected={_session.Client.IsConnected} steamid={_session.Client.SteamID} " +
                $"pump={SteamSession.PumpIterations} faults={SteamSession.PumpFaults} " +
                $"callbacks={SteamSession.CallbacksSeen}");

            if (_session.Client.IsConnected)
            {
                if (attempts > 0)
                    JsonOutput.Emit(new Dictionary<string, object?> { ["connection_restored"] = true });
                attempts = 0;
                lock (_announceGate)
                {
                    if (_currentApp != 0) Announce(_currentApp);
                }

                // Persona state is last-writer-wins across an account's
                // sessions, exactly like games-played, so it needs the same
                // periodic defence — but far less often, since nothing else
                // asserts it continuously and Steam pushes the real value
                // back unprompted whenever it changes.
                if (++ticks % 12 == 0) _friends.SetPersonaState(_currentState);
                continue;
            }

            // Displaced by another logon on this account — almost always
            // the real Steam client. Reconnecting would just kick that one
            // back, and the two would trade the account indefinitely.
            if (_displaced)
            {
                JsonOutput.Emit(new Dictionary<string, object?>
                {
                    ["error"] = "Steam signed this session out because the account logged on somewhere else. Reopen BEER to restore status and play-time tracking.",
                    ["fatal"] = true,
                });
                // Nothing this process can still do is useful, and the app
                // watches for it exiting to clear the status it shows.
                Environment.Exit(1);
                return;
            }

            // A CM dropping a long-lived client is routine, so reconnect —
            // the session's existing ConnectedCallback logs back on. Back
            // off so a persistent outage doesn't hammer Steam's rate limit.
            attempts++;
            if (attempts > 10)
            {
                JsonOutput.Emit(new Dictionary<string, object?>
                {
                    ["error"] = "Lost the Steam connection and couldn't get it back. Status and play time aren't being recorded.",
                    ["fatal"] = true,
                });
                Environment.Exit(1);
                return;
            }
            JsonOutput.Emit(new Dictionary<string, object?> { ["reconnecting"] = attempts });
            try { _session.Client.Connect(); } catch { /* next tick retries */ }
            try { await Task.Delay(TimeSpan.FromSeconds(Math.Min(5 * attempts, 30)), token); }
            catch (OperationCanceledException) { break; }
        }
    }
}
