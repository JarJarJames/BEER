using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Tests.Steam;

// The app shows "wait" for a rate limit and "sign in again" for anything else.
// Getting this wrong either strands a revoked token or sends the user to the
// QR sheet during a throttle, which only extends the cooldown.
public class LogonFailedExceptionTests
{
    [Theory]
    [InlineData(EResult.RateLimitExceeded)]
    [InlineData(EResult.AccountLoginDeniedThrottle)]
    [InlineData(EResult.TryAnotherCM)]
    [InlineData(EResult.ServiceUnavailable)]
    [InlineData(EResult.Busy)]
    public void Throttles_are_rate_limited(EResult result)
    {
        Assert.True(new LogonFailedException("logon failed", result).IsRateLimited);
    }

    [Theory]
    [InlineData(EResult.InvalidPassword)]
    [InlineData(EResult.AccessDenied)]
    [InlineData(EResult.Expired)]
    [InlineData(EResult.Revoked)]
    public void Credential_failures_are_not_rate_limited(EResult result)
    {
        Assert.False(new LogonFailedException("logon failed", result).IsRateLimited);
    }
}
