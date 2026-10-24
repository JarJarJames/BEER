using System.Text.Json;

namespace CloudSync.Cli;

/// Writes one JSON object per line to stdout. Every write goes through one
/// lock: presence emits from Steam callbacks and its keepalive thread at once,
/// and batch emits from concurrent transfers.
static class JsonOutput
{
    static readonly object Lock = new();

    public static void Emit(object o)
    {
        // Serialize outside the lock/try-free path so a failure here (rather
        // than in the write itself) is distinguishable in the trace, and
        // flush explicitly rather than trusting Console.Out's autoflush —
        // belt-and-suspenders for a helper whose final line has gone missing
        // for reasons still being tracked down.
        var json = JsonSerializer.Serialize(o);
        WriteLine(json);
    }

    /// Write an already-serialized JSON line.
    public static void WriteLine(string json)
    {
        lock (Lock)
        {
            Console.WriteLine(json);
            Console.Out.Flush();
        }
    }
}
