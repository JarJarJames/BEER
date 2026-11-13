using SteamKit2;
using SteamKit2.Internal;

namespace CloudSync.Commands.Presence;

static class PersonaStatus
{
    // The status change BEER sends: the one the user picked, marked as picked
    // by the user.
    //
    // SteamKit2's SteamFriends.SetPersonaState sends only the state. Without
    // persona_set_by_user Steam treats the change as automatic rather than
    // the user's choice, and with the account signed in on other devices
    // that signed the user's own Steam client out of Friends every time BEER
    // set its status (#65). JavaSteam — what GameNative runs on, which sits
    // beside a desktop Steam client without trouble — sets the flag for
    // exactly this reason (JavaSteam b77762f2, "Fixes setPersonaState() to
    // actually change your stage when you are logged in on multiple clients").
    public static ClientMsgProtobuf<CMsgClientChangeStatus> Message(EPersonaState state)
    {
        var msg = new ClientMsgProtobuf<CMsgClientChangeStatus>(EMsg.ClientChangeStatus);
        msg.Body.persona_state = (uint)state;
        msg.Body.persona_set_by_user = true;
        return msg;
    }
}
