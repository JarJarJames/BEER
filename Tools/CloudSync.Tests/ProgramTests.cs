using System.Text.Json;

namespace CloudSync.Tests;

// The Swift app decodes the helper's last stdout line and its exit code, so
// both are part of the contract. These cases fail before any Steam logon.
[Collection(ConsoleCollection.Name)]
public class ProgramTests
{
    static async Task<(int ExitCode, string Stdout)> RunAsync(params string[] args)
    {
        var originalOut = Console.Out;
        var originalError = Console.Error;
        using var stdout = new StringWriter();
        Console.SetOut(stdout);
        Console.SetError(TextWriter.Null);
        try
        {
            var exitCode = await Program.Main(args);
            return (exitCode, stdout.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
            Console.SetError(originalError);
        }
    }

    [Fact]
    public async Task No_arguments_is_a_usage_error()
    {
        var (exitCode, stdout) = await RunAsync();

        Assert.Equal(2, exitCode);
        Assert.Empty(stdout);
    }

    [Fact]
    public async Task A_missing_token_is_reported_as_a_json_error()
    {
        var (exitCode, stdout) = await RunAsync("enumerate", "--appid", "1", "--account", "someone");

        Assert.Equal(1, exitCode);
        using var json = JsonDocument.Parse(stdout);
        Assert.Equal("missing --token-file or --token", json.RootElement.GetProperty("error").GetString());
        Assert.False(json.RootElement.TryGetProperty("auth_failed", out _));
        Assert.False(json.RootElement.TryGetProperty("rate_limited", out _));
    }
}

[CollectionDefinition(Name, DisableParallelization = true)]
public class ConsoleCollection
{
    public const string Name = "Console redirection";
}
