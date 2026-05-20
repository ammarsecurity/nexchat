namespace NexChat.API.Services.StockVideo;

public static class StockVideoUrlValidator
{
    private static readonly string[] AllowedVideoHosts =
    [
        "videos.pexels.com",
        "player.vimeo.com",
        "cdn.pixabay.com",
        "pixabay.com"
    ];

    private static readonly string[] AllowedImageHosts =
    [
        "images.pexels.com",
        "i.vimeocdn.com",
        "cdn.pixabay.com",
        "pixabay.com"
    ];

    public static bool IsAllowedVideoUrl(string? url) => IsAllowed(url, AllowedVideoHosts);

    public static bool IsAllowedImageUrl(string? url) => IsAllowed(url, AllowedImageHosts);

    private static bool IsAllowed(string? url, string[] hosts)
    {
        if (string.IsNullOrWhiteSpace(url)) return false;
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return false;
        if (uri.Scheme is not "https" and not "http") return false;
        var host = uri.Host.ToLowerInvariant();
        return hosts.Any(h => host == h || host.EndsWith("." + h, StringComparison.Ordinal));
    }
}
