using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Tests.Steam;

public class SteamSessionTests
{
    // Regression for #65: a legacy-chat logon signed the user's own Steam
    // clients out of Friends whenever BEER opened.
    [Fact]
    public void LogsOnAsANewChatClient() =>
        Assert.Equal(SteamUser.ChatMode.NewSteamChat,
            SteamSession.LogOnDetails("someone", "token", 1234).ChatMode);

    [Fact]
    public void KeepsItsOwnLoginID() =>
        Assert.Equal(1234u, SteamSession.LogOnDetails("someone", "token", 1234).LoginID);

    [Fact]
    public void LogsOnWithTheRefreshToken()
    {
        var details = SteamSession.LogOnDetails("someone", "token", 1234);
        Assert.Equal("someone", details.Username);
        Assert.Equal("token", details.AccessToken);
        Assert.Null(details.Password);
    }
}
