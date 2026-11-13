using CloudSync.Cli;

namespace CloudSync.Tests.Cli;

public class SessionRequestTests
{
    [Fact]
    public void ReadsIdCommandAndArgs()
    {
        var request = SessionRequest.Parse("""{"id":7,"cmd":"enumerate","args":{"appid":"440","flag":"true"}}""");
        Assert.Equal(7, request.Id);
        Assert.Equal("enumerate", request.Command);
        Assert.Equal("440", request.Args["appid"]);
        Assert.Equal("true", request.Args["flag"]);
    }

    [Fact]
    public void ArgsAreOptional() =>
        Assert.Empty(SessionRequest.Parse("""{"id":1,"cmd":"dlc"}""").Args);

    [Fact]
    public void ARequestWithoutACommandIsRejected() =>
        Assert.ThrowsAny<Exception>(() => SessionRequest.Parse("""{"id":1}"""));
}
