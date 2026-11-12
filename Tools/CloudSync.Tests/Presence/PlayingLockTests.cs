using CloudSync.Commands.Presence;

namespace CloudSync.Tests.Presence;

// Regression for #65: announcing a game while another device holds the
// account's playing slot, or right as it lets go, signs that device out with
// LoggedInElsewhere.
public class PlayingLockTests
{
    static readonly DateTime T0 = new(2026, 11, 12, 12, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void ClaimsWhenNothingElseIsPlaying() => Assert.True(new PlayingLock().MayClaim(T0));

    [Fact]
    public void NeverClaimsWhileAnotherDeviceIsPlaying()
    {
        var gate = new PlayingLock();
        gate.Update(blocked: true, T0);
        Assert.False(gate.MayClaim(T0));
        Assert.False(gate.MayClaim(T0.AddHours(3)));
    }

    [Fact]
    public void WaitsOutTheCooldownAfterTheOtherDeviceStops()
    {
        var gate = new PlayingLock();
        gate.Update(blocked: true, T0);
        gate.Update(blocked: false, T0.AddMinutes(5));

        Assert.False(gate.MayClaim(T0.AddMinutes(5)));
        Assert.False(gate.MayClaim(T0.AddMinutes(5) + PlayingLock.Cooldown - TimeSpan.FromSeconds(1)));
        Assert.True(gate.MayClaim(T0.AddMinutes(5) + PlayingLock.Cooldown));
    }

    [Fact]
    public void AReconnectAfterABlockStartsTheCooldown()
    {
        var gate = new PlayingLock();
        gate.Update(blocked: true, T0);
        // What the presence session does after every logon.
        gate.Update(blocked: false, T0.AddMinutes(1));
        Assert.False(gate.MayClaim(T0.AddMinutes(1)));
    }

    [Fact]
    public void AReconnectWithNoBlockDoesNotDelay()
    {
        var gate = new PlayingLock();
        gate.Update(blocked: false, T0);
        Assert.True(gate.MayClaim(T0));
    }
}
