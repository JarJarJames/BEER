using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Tests.Steam;

public class SteamSessionTests
{
    // The user's own Steam clients use new chat, as do ArchiSteamFarm,
    // GameNative and node-steam-user; SteamKit's default is legacy chat.
    [Fact]
    public void LogsOnAsANewChatClient() =>
        Assert.Equal(SteamUser.ChatMode.NewSteamChat,
            SteamSession.LogOnDetails("someone", "token", 1234).ChatMode);

    // Regression for #65: logged on as macOS, BEER and the Mac's own Steam
    // client signed each other out of Friends.
    [Fact]
    public void DoesNotLogOnAsTheMacsOwnOS()
    {
        var os = SteamSession.LogOnDetails("someone", "token", 1234).ClientOSType;
        Assert.Equal(EOSType.LinuxUnknown, os);
        Assert.DoesNotContain("Mac", os.ToString());
    }

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
