namespace NexChat.API.Services.StockVideo;

public sealed class StockVideoItem
{
    public required string Provider { get; init; }
    public required string ExternalId { get; init; }
    public required string Title { get; init; }
    public string? Description { get; init; }
    public required string ThumbnailUrl { get; init; }
    public required string VideoDownloadUrl { get; init; }
    public int? DurationSeconds { get; init; }
    public string? AuthorName { get; init; }
    public string? SourcePageUrl { get; init; }
}

public sealed class StockVideoSearchPage
{
    public required IReadOnlyList<StockVideoItem> Items { get; init; }
    public int Page { get; init; }
    public int PerPage { get; init; }
    public int TotalResults { get; init; }
    public bool HasMore { get; init; }
}
