using CloudSync.Cli;
using CloudSync.Steam;
using SteamKit2;
using SteamKit2.Authentication;
using SteamKit2.Internal;

namespace CloudSync.Commands;

static class AuthCommand
{
    // QR sign-in that yields a SteamClient-audience refresh token (the kind the
    // Cloud client protocol accepts). Emits the challenge URL as JSON so the
    // Swift UI can render the QR, re-emits on rotation, then emits the token.
    public static async Task RunAsync()
    {
        using var session = await SteamSession.ConnectOnlyAsync();

        var authSession = await session.Client.Authentication.BeginAuthSessionViaQRAsync(new AuthSessionDetails
        {
            PlatformType = EAuthTokenPlatformType.k_EAuthTokenPlatformType_SteamClient,
            DeviceFriendlyName = "BEER for Mac",
            ClientOSType = EOSType.MacOS1020,
            IsPersistentSession = true,
        });

        void EmitChallenge() => JsonOutput.Emit(new Dictionary<string, object?>
        {
            ["challenge_url"] = authSession.ChallengeURL,
        });

        authSession.ChallengeURLChanged = EmitChallenge;
        EmitChallenge();

        var poll = await authSession.PollingWaitForResultAsync();
        session.Disconnect();

        JsonOutput.Emit(new Dictionary<string, object?>
        {
            ["authenticated"] = true,
            ["account"] = poll.AccountName,
            ["refresh_token"] = poll.RefreshToken,
        });
    }
}
