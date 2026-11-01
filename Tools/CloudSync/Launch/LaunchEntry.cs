namespace CloudSync.Launch;

/// One Windows launch option from an app's `config/launch` section. Paths are
/// relative to the install root, exactly as Steam stores them (backslashes).
sealed record LaunchEntry(
    string Executable,
    string Arguments,
    string WorkingDir,
    string Type,
    string Description);
