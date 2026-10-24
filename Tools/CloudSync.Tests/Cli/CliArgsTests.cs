using CloudSync.Cli;

namespace CloudSync.Tests.Cli;

public class CliArgsTests
{
    [Fact]
    public void Parse_takes_the_first_bare_word_as_the_command()
    {
        var args = CliArgs.Parse(["enumerate", "--appid", "379430"]);

        Assert.Equal("enumerate", args["_cmd"]);
        Assert.Equal("379430", args["appid"]);
    }

    [Fact]
    public void Parse_treats_a_flag_with_no_value_as_true()
    {
        var args = CliArgs.Parse(["batch", "--verbose", "--appid", "1"]);

        Assert.Equal("true", args["verbose"]);
        Assert.Equal("1", args["appid"]);
    }

    [Fact]
    public void Parse_has_no_command_when_the_first_word_is_a_flag()
    {
        var args = CliArgs.Parse(["--appid", "1"]);

        Assert.False(args.ContainsKey("_cmd"));
    }

    [Fact]
    public void Require_names_the_missing_flag()
    {
        var ex = Assert.Throws<Exception>(() => CliArgs.Require(new Dictionary<string, string>(), "steamid"));

        Assert.Equal("missing --steamid", ex.Message);
    }

    [Fact]
    public void ReadToken_prefers_the_token_file_and_trims_it()
    {
        var path = Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, "  file-token\n");
            var args = new Dictionary<string, string> { ["token-file"] = path, ["token"] = "argv-token" };

            Assert.Equal("file-token", CliArgs.ReadToken(args));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ReadToken_fails_without_either_source()
    {
        var ex = Assert.Throws<Exception>(() => CliArgs.ReadToken(new Dictionary<string, string>()));

        Assert.Equal("missing --token-file or --token", ex.Message);
    }
}
