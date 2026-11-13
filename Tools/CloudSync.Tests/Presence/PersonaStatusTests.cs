using CloudSync.Commands.Presence;
using SteamKit2;

namespace CloudSync.Tests.Presence;

// Regression for #65: SteamKit2's SetPersonaState leaves persona_set_by_user
// off, and that status change signed the user's own Steam client out of
// Friends. JavaSteam (GameNative) sets it; so does BEER.
public class PersonaStatusTests
{
    [Theory]
    [InlineData(EPersonaState.Online)]
    [InlineData(EPersonaState.Away)]
    [InlineData(EPersonaState.Invisible)]
    [InlineData(EPersonaState.Offline)]
    public void IsSentAsTheUsersOwnChoice(EPersonaState state)
    {
        var msg = PersonaStatus.Message(state);
        Assert.Equal(EMsg.ClientChangeStatus, msg.MsgType);
        Assert.Equal((uint)state, msg.Body.persona_state);
        Assert.True(msg.Body.persona_set_by_user);
    }
}
