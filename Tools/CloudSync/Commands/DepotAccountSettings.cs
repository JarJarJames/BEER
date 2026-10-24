using System.Collections.Concurrent;
using ProtoBuf;

namespace CloudSync.Commands;

/// DepotDownloader's `account.config` layout (protobuf, deflate-compressed).
/// Field numbers must match DepotDownloader's own `AccountSettingsStore`.
[ProtoContract]
sealed class DepotAccountSettings
{
    [ProtoMember(2)]
    public ConcurrentDictionary<string, int> ContentServerPenalty { get; } = new();

    [ProtoMember(4)]
    public Dictionary<string, string> LoginTokens { get; } =
        new(StringComparer.OrdinalIgnoreCase);

    [ProtoMember(5)]
    public Dictionary<string, string> GuardData { get; } =
        new(StringComparer.OrdinalIgnoreCase);
}
