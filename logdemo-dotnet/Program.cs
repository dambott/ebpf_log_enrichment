using System.Text.Json;

// OBI requires synchronous JSON writes to stdout on the request thread.
// Avoid ILogger/AddConsole — it writes from a background thread.
var stdout = new StreamWriter(Console.OpenStandardOutput()) { AutoFlush = true };
var jsonOpts = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

void LogJson(string level, string msg, Dictionary<string, object>? fields = null)
{
    var payload = new Dictionary<string, object> { ["level"] = level, ["msg"] = msg };
    if (fields is not null)
    {
        foreach (var (key, value) in fields)
            payload[key] = value;
    }
    stdout.WriteLine(JsonSerializer.Serialize(payload, jsonOpts));
}

var builder = WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders();
builder.WebHost.UseUrls("http://0.0.0.0:8085");

var app = builder.Build();

app.MapGet("/health", () => Results.Text("ok", "text/plain"));
app.MapGet("/smoke", () => Results.Text("ok", "text/plain"));
app.MapGet("/work", () =>
{
    Thread.Sleep(50);
    LogJson("INFO", "request complete", new Dictionary<string, object>
    {
        ["route"] = "/work",
        ["duration_ms"] = 50,
    });
    return Results.Json(new { status = "ok" });
});

LogJson("INFO", "server start", new Dictionary<string, object> { ["port"] = 8085 });
app.Run();
