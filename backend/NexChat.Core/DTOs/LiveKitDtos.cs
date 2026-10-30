namespace NexChat.Core.DTOs;

public class LiveKitConfigDto
{
    /// <summary>WebSocket URL for clients, e.g. wss://livekit.example.com</summary>
    public string Url { get; set; } = "";

    public string ApiKey { get; set; } = "";

    public string ApiSecret { get; set; } = "";
}

public record LiveKitProbeCheckDto(string Name, bool Ok, string? Detail = null);

public record LiveKitProbeResultDto(
    bool Ok,
    bool Configured,
    string? Url,
    string? HttpHost,
    int? LatencyMs,
    int? RoomCount,
    string Message,
    IReadOnlyList<LiveKitProbeCheckDto> Checks
);
