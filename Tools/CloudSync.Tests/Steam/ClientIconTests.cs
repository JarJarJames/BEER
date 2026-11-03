using CloudSync.Steam;
using SteamKit2;

namespace CloudSync.Tests.Steam;

// Fixtures mirror the `common` section of PICS app info.
public class ClientIconTests
{
    static KeyValue App(string? clientIcon)
    {
        var root = new KeyValue("appinfo");
        var common = new KeyValue("common");
        root["common"] = common;
        if (clientIcon is not null) common["clienticon"] = new KeyValue("clienticon", clientIcon);
        return root;
    }

    [Fact]
    public void ReadsTheHash() =>
        Assert.Equal("295fac0ec6dbaf1f7f7cdf0c7bf359ab84ccc7cf",
            ClientIcon.Hash(App("295FAC0EC6DBAF1F7F7CDF0C7BF359AB84CCC7CF")));

    [Fact]
    public void NullWhenMissing() => Assert.Null(ClientIcon.Hash(App(null)));

    [Theory]
    [InlineData("")]
    [InlineData("not-a-hash")]
    [InlineData("../../../../etc/passwd/0000000000000000000000")]
    public void NullWhenNotAHash(string value) => Assert.Null(ClientIcon.Hash(App(value)));
}
