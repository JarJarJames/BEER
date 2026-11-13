using SteamKit2;
using SteamKit2.Internal;

namespace CloudSync.Commands.Presence;

static class PersonaStatus
{
    // The status change BEER sends: the one the user picked, marked as picked
    // by the user — what Steam's own client sends when the user chooses a
    // status (FriendStore.SendPersonaStateToServer sets persona_set_by_user).
    // SteamKit2's SteamFriends.SetPersonaState sends only the state, which
    // Steam treats as automatic. JavaSteam sets the flag too (b77762f2,
    // "Fixes setPersonaState() to actually change your stage when you are
    // logged in on multiple clients").
    public static ClientMsgProtobuf<CMsgClientChangeStatus> Message(EPersonaState state)
    {
        var msg = new ClientMsgProtobuf<CMsgClientChangeStatus>(EMsg.ClientChangeStatus);
        msg.Body.persona_state = (uint)state;
        msg.Body.persona_set_by_user = true;
        return msg;
    }
}
