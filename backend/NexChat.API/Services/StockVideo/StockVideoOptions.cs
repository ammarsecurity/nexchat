namespace NexChat.API.Services.StockVideo;

public class StockVideoOptions
{
    public const string SectionName = "StockVideo";

    public string? PexelsApiKey { get; set; }
    public string? PixabayApiKey { get; set; }
    public int MaxVideoBytes { get; set; } = 50 * 1024 * 1024;
    public int MaxThumbnailBytes { get; set; } = 10 * 1024 * 1024;
}
