using CloudSync.Commands.Presence;
using SteamKit2;

namespace CloudSync.Tests.Presence;

// Regression for #65: Offline is account-wide and signs every device out of
// Friends & Chat, so BEER must never send it.
public class PersonaPolicyTests
{
    [Fact]
    public void OfflineIsSentAsInvisible() =>
        Assert.Equal(EPersonaState.Invisible, PersonaPolicy.Assertable(EPersonaState.Offline));

    [Theory]
    [InlineData(EPersonaState.Online)]
    [InlineData(EPersonaState.Away)]
    [InlineData(EPersonaState.Invisible)]
    public void OtherStatesPassThrough(EPersonaState state) =>
        Assert.Equal(state, PersonaPolicy.Assertable(state));
}
