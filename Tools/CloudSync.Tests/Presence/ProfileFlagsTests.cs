using CloudSync.Commands.Presence;
using SteamKit2;

namespace CloudSync.Tests.Presence;

// Regression for #65: asking Steam for the account's own profile with the
// Status flag made Steam send the account's sessions an update saying
// Offline, and the user's Steam client on their PC signed itself out of
// Friends on receiving it.
public class ProfileFlagsTests
{
    [Fact]
    public void NeverAsksForStatus() =>
        Assert.False(PresenceSession.ProfileFlags.HasFlag(EClientPersonaStateFlag.Status));

    [Fact]
    public void StillGetsTheNameAndAvatar()
    {
        Assert.True(PresenceSession.ProfileFlags.HasFlag(EClientPersonaStateFlag.PlayerName));
        Assert.True(PresenceSession.ProfileFlags.HasFlag(EClientPersonaStateFlag.Presence));
    }
}
