namespace CloudSync.Steam;

/// A depot DepotDownloader would fetch for a Windows install. `DlcAppId` is
/// set when the depot belongs to a DLC the account owns; `Size` is null when
/// Steam lists none.
public sealed record FetchedDepot(uint Id, uint? DlcAppId, ulong? Size);
