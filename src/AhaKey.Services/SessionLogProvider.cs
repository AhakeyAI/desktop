using System.Collections.Concurrent;
using Microsoft.Extensions.Logging;
namespace AhaKey.Services;
// Structured operational events and approved telemetry frames; no device IDs or user paths.
public sealed class SessionLogProvider : ILoggerProvider
{
    private readonly object fileGate=new();
    public string DirectoryPath {get;}
    public string FilePath {get;private set;}
    public SessionLogProvider(SettingsStore? settings=null)
    {
        DirectoryPath=Path.Combine((settings??new SettingsStore()).Root,"Logs");
        FilePath=Path.Combine(DirectoryPath,$"studio-{DateTime.UtcNow:yyyyMMdd-HHmmss}-{Environment.ProcessId}.log");
        try {Directory.CreateDirectory(DirectoryPath);Trim();}catch(Exception ex) when(ex is IOException or UnauthorizedAccessException) { }
    }
    private void Trim()
    {foreach(var old in new DirectoryInfo(DirectoryPath).GetFiles("studio-*.log").OrderByDescending(f=>f.LastWriteTimeUtc).Skip(4))old.Delete();}
    private void Append(string line)
    {
        lock(fileGate)
        {
            events.Enqueue(line);while(events.Count>200)events.TryDequeue(out _);
            try
            {
                if(File.Exists(FilePath) && new FileInfo(FilePath).Length>2_000_000)
                {FilePath=Path.Combine(DirectoryPath,$"studio-{DateTime.UtcNow:yyyyMMdd-HHmmss-fffffff}-{Environment.ProcessId}.log");Trim();}
                File.AppendAllText(FilePath,line+Environment.NewLine);
            }
            catch(Exception ex) when(ex is IOException or UnauthorizedAccessException) { }
        }
    }
    private readonly ConcurrentQueue<string> events = new();
    public IReadOnlyList<string> Entries => events.ToArray();
    public ILogger CreateLogger(string categoryName) => new SessionLogger(this, categoryName);
    public void Dispose() { }
    private sealed class SessionLogger(SessionLogProvider owner, string category) : ILogger
    {
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => logLevel >= LogLevel.Information;
        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            if (!IsEnabled(logLevel)) return;
            owner.Append($"{DateTimeOffset.UtcNow:O} {logLevel} {category}: {formatter(state, exception)}"+(exception is null?"":$"; exception={exception.GetType().Name}; HRESULT=0x{exception.HResult:X8}; stack={new System.Diagnostics.StackTrace(exception,false).ToString().Replace(Environment.NewLine," | ")}"));
        }
    }
}
