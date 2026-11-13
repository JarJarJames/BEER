using CloudSync.Cli;
using SteamKit2;
using SteamKit2.Internal;

namespace CloudSync.Commands.Presence;

// Logs every status update Steam pushes about the signed-in account itself,
// with the fields SteamKit2's PersonaStateCallback leaves out.
//
// Why: Steam's own client signs itself out of Friends when it is pushed a
// status for its account of Offline with persona_set_by_user set
// (FriendStore.UpdateUserPersonaStateInternal in the client's steamui
// sp.js: `re == Offline && setByUser && SignOutOfFriends()`). Steam pushes
// the account's status to every session on it, so what this session
// receives is what the user's other Steam clients receive (#65).
sealed class SelfPersonaTrace : ClientMsgHandler
{
    public override void HandleMsg(IPacketMsg packetMsg)
    {
        if (packetMsg.MsgType != EMsg.ClientPersonaState || Client.SteamID is not { } self) return;
        var msg = new ClientMsgProtobuf<CMsgClientPersonaState>(packetMsg);
        foreach (var friend in msg.Body.friends)
        {
            if (friend.friendid != self.ConvertToUInt64()) continue;
            JsonOutput.Emit(new Dictionary<string, object?>
            {
                ["self_persona_push"] = new Dictionary<string, object?>
                {
                    ["status_flags"] = msg.Body.status_flags,
                    ["persona_state"] = ((EPersonaState)friend.persona_state).ToString(),
                    ["persona_set_by_user"] = friend.ShouldSerializepersona_set_by_user() ? friend.persona_set_by_user : null,
                    ["persona_state_flags"] = friend.persona_state_flags,
                    ["online_session_instances"] = friend.online_session_instances,
                    ["game_played_app_id"] = friend.game_played_app_id,
                },
            });
        }
    }
}
