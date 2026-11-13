using CloudSync.Commands.Presence;
using SteamKit2;

namespace CloudSync.Tests.Presence;

// A status the user picks goes out marked as theirs, as Steam's own client
// sends it; SteamKit2's SetPersonaState leaves persona_set_by_user off.
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
