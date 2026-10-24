using SteamKit2;
using SteamKit2.Internal;

namespace CloudSync.Steam;

// Owns a logged-on SteamClient + the Cloud unified service. Pumps callbacks on
// a background thread for the lifetime of the session.
sealed class SteamSession : IDisposable
{
    // Instrumentation. A session that quietly stops receiving callbacks looks
    // identical to a healthy idle one, so these make the difference visible.
    public static long PumpIterations;
    public static long PumpFaults;
    public static long CallbacksSeen;

    public SteamClient Client { get; }
    public Cloud Cloud { get; private set; } = null!;
    public SteamUnifiedMessages Unified { get; private set; } = null!;
    public UserStatsHandler UserStats { get; } = new();
    readonly CallbackManager _cb;
    readonly CancellationTokenSource _pump = new();
    readonly TaskCompletionSource<List<SteamApps.LicenseListCallback.License>> _licenses =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    /// The account's package licences, which Steam pushes shortly after logon.
    /// Ownership of a DLC can only be derived from these, so callers wait for
    /// the push rather than racing it.
    public async Task<List<SteamApps.LicenseListCallback.License>> LicensesAsync()
    {
        var timeout = Task.Delay(TimeSpan.FromSeconds(30));
        if (await Task.WhenAny(_licenses.Task, timeout) == timeout)
            throw new Exception("timed out waiting for Steam to send the account's licenses");
        return await _licenses.Task;
    }

    SteamSession(SteamClient client, CallbackManager cb)
    {
        Client = client; _cb = cb;
    }

    /// Subscribe to a Steam callback for the life of this session.
    public void Subscribe<T>(Action<T> handler) where T : CallbackMsg
        => _cb.Subscribe(handler);

    static SteamSession StartPump()
    {
        var client = new SteamClient();
        var cb = new CallbackManager(client);
        var session = new SteamSession(client, cb);
        client.AddHandler(session.UserStats);
        var token = session._pump.Token;
        _ = Task.Run(() =>
        {
            try
            {
            while (!token.IsCancellationRequested)
            {
                // A throwing handler must never take the pump down with it.
                // Unguarded, one bad callback silently ends callback delivery
                // for the rest of the session: the connection still looks alive
                // and commands still appear to work, but nothing Steam sends
                // back — persona updates, disconnects, logoff reasons — is ever
                // seen again. Short-lived commands got away with it; a session
                // that runs for hours does not.
                try
                {
                    cb.RunWaitCallbacks(TimeSpan.FromMilliseconds(200));
                    Interlocked.Increment(ref PumpIterations);
                }
                catch (Exception ex)
                {
                    Interlocked.Increment(ref PumpFaults);
                    try { Console.Error.WriteLine($"callback handler threw: {ex}"); } catch { }
                }
            }
            }
            finally { Console.Error.WriteLine($"callback pump stopped after {PumpIterations} iterations."); }
        });
        return session;
    }

    /// Connect to a CM server without logging on (used by the QR auth flow,
    /// which establishes its own session via the authentication service).
    public static async Task<SteamSession> ConnectOnlyAsync()
    {
        var session = StartPump();
        var connected = new TaskCompletionSource();
        session._cb.Subscribe<SteamClient.ConnectedCallback>(_ => connected.TrySetResult());
        session._cb.Subscribe<SteamClient.DisconnectedCallback>(_ =>
        {
            if (!connected.Task.IsCompleted) connected.TrySetException(new Exception("disconnected before connect"));
        });
        session.Client.Connect();
        var timeout = Task.Delay(TimeSpan.FromSeconds(45));
        if (await Task.WhenAny(connected.Task, timeout) == timeout)
            throw new Exception("timed out connecting to Steam");
        await connected.Task;
        Console.Error.WriteLine("connected (no logon).");
        return session;
    }

    /// Connect and log on with a SteamClient-audience refresh token, then bind
    /// the Cloud unified service.
    // Steam tells concurrent sessions on one account apart by LoginID. Left
    // unset they all collide on the same default — so every new logon evicts
    // the last with LogonSessionReplaced. That includes our own short-lived
    // commands evicting the long-lived presence session, and the user's real
    // Steam client evicting both.
    //
    // The presence session gets a fixed id so its own reconnects keep one
    // identity; every other command gets a random one, so a library refresh or
    // a cloud sync can't knock presence offline mid-game.
    public const uint PresenceLoginID = 0x42454552; // "BEER"
    public static readonly uint CommandLoginID = (uint)Random.Shared.Next(1, int.MaxValue);

    /// Log on, retrying a connection that drops before the logon completes.
    ///
    /// Steam's CMs drop connections routinely — especially after a burst of
    /// logons, which is exactly what a game crashing and being relaunched
    /// produces. Treating the first drop as fatal turns one transient refusal
    /// into a dead presence session and a failed library refresh at the same
    /// moment.
    ///
    /// A refusal Steam actually explains (bad token, rate limit) is NOT retried:
    /// re-attempting those only deepens the cooldown.
    public static async Task<SteamSession> LogOnAsync(string account, string refreshToken, uint loginID)
    {
        Exception? last = null;
        for (var attempt = 1; attempt <= 4; attempt++)
        {
            try
            {
                return await LogOnOnceAsync(account, refreshToken, loginID);
            }
            catch (LogonFailedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                last = ex;
                Console.Error.WriteLine($"logon attempt {attempt}/4 failed: {ex.Message}");
                if (attempt < 4)
                    await Task.Delay(TimeSpan.FromSeconds(Math.Pow(2, attempt)));
            }
        }
        throw last!;
    }

    static async Task<SteamSession> LogOnOnceAsync(string account, string refreshToken, uint loginID)
    {
        var session = StartPump();
        var user = session.Client.GetHandler<SteamUser>()!;
        var unified = session.Client.GetHandler<SteamUnifiedMessages>()!;
        // RunContinuationsAsynchronously is load-bearing, not a style choice.
        // Without it, TrySetResult below runs everything awaiting this task
        // inline on the callback pump thread — so the command itself ends up
        // executing there. A command that suspends gives the thread back; one
        // that parks on a blocking read never does, and the pump stops
        // dispatching for good: no disconnects, no reconnect logons, no persona
        // updates, while the process looks perfectly healthy.
        var loggedOn = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        session._cb.Subscribe<SteamClient.ConnectedCallback>(_ =>
        {
            Console.Error.WriteLine("connected; logging on…");
            user.LogOn(new SteamUser.LogOnDetails
            {
                Username = account,
                AccessToken = refreshToken,
                ShouldRememberPassword = true,
                LoginID = loginID,
            });
        });
        session._cb.Subscribe<SteamClient.DisconnectedCallback>(_ =>
        {
            if (!loggedOn.Task.IsCompleted)
                loggedOn.TrySetException(new Exception("disconnected before logon completed"));
            session._licenses.TrySetException(new Exception("disconnected before licenses arrived"));
        });
        session._cb.Subscribe<SteamApps.LicenseListCallback>(l =>
        {
            if (l.Result == EResult.OK)
                session._licenses.TrySetResult(l.LicenseList.ToList());
            else
                session._licenses.TrySetException(new Exception($"license list failed: {l.Result}"));
        });
        session._cb.Subscribe<SteamUser.LoggedOnCallback>(l =>
        {
            if (l.Result == EResult.OK) loggedOn.TrySetResult();
            else loggedOn.TrySetException(new LogonFailedException($"logon failed: {l.Result} / {l.ExtendedResult}", l.Result));
        });

        session.Unified = unified;
        session.Cloud = unified.CreateService<Cloud>();
        session.Client.Connect();

        try
        {
            var timeout = Task.Delay(TimeSpan.FromSeconds(45));
            if (await Task.WhenAny(loggedOn.Task, timeout) == timeout)
                throw new Exception("timed out connecting/logging on to Steam");
            await loggedOn.Task; // surface logon exception if any
        }
        catch
        {
            // Each attempt builds a fresh client and pump thread; a failed one
            // has to be torn down or a retry leaks both.
            session.Disconnect();
            session.Dispose();
            throw;
        }

        Console.Error.WriteLine("logged on.");
        return session;
    }

    public void Disconnect()
    {
        try { Client.GetHandler<SteamUser>()?.LogOff(); } catch { }
        try { Client.Disconnect(); } catch { }
    }

    public void Dispose() => _pump.Cancel();
}
