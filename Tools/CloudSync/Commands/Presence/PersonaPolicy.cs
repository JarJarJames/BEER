using SteamKit2;

namespace CloudSync.Commands.Presence;

static class PersonaPolicy
{
    // Persona state belongs to the account, not this session. Offline signs
    // every device out of Friends & Chat — the user's Steam client on the PC
    // and on this Mac included — and BEER applies its status at every logon,
    // so sending it signed those devices out each time BEER opened. Invisible
    // hides the user the same way without signing anyone out.
    public static EPersonaState Assertable(EPersonaState wanted) =>
        wanted == EPersonaState.Offline ? EPersonaState.Invisible : wanted;
}
