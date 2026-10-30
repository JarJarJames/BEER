using SteamKit2;

namespace CloudSync.Steam;

// Thrown when a Steam logon fails. Carries the EResult so the app can tell a
// genuine credential failure (needs a fresh QR sign-in) apart from a transient
// throttle (just wait and retry — re-auth would only burn more logons).
sealed class LogonFailedException : Exception
{
    public EResult Result { get; }
    public LogonFailedException(string message, EResult result) : base(message) { Result = result; }

    // Steam temporarily refused the logon (too many recent logins, CM busy…).
    public bool IsRateLimited => Result is EResult.RateLimitExceeded
        or EResult.AccountLoginDeniedThrottle
        or EResult.TryAnotherCM
        or EResult.ServiceUnavailable
        or EResult.Busy;
}
