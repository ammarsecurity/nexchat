using System.Text.Json;
using Microsoft.Extensions.Options;

namespace NexChat.API.Services.StockVideo;

public class StockVideoCatalogService(
    HttpClient http,
    IOptions<StockVideoOptions> options)
{
    private readonly StockVideoOptions _opts = options.Value;

    public IReadOnlyList<string> GetConfiguredProviders()
    {
        var list = new List<string>();
        if (!string.IsNullOrWhiteSpace(_opts.PexelsApiKey)) list.Add("pexels");
        if (!string.IsNullOrWhiteSpace(_opts.PixabayApiKey)) list.Add("pixabay");
        return list;
    }

    public async Task<StockVideoSearchPage> SearchAsync(string provider, string query, int page, CancellationToken ct = default)
    {
        provider = provider.Trim().ToLowerInvariant();
        page = Math.Max(1, page);
        query = query.Trim();
        if (string.IsNullOrWhiteSpace(query))
            throw new ArgumentException("Query is required");

        return provider switch
        {
            "pexels" => await SearchPexelsAsync(query, page, ct),
            "pixabay" => await SearchPixabayAsync(query, page, ct),
            _ => throw new ArgumentException("Unknown provider. Use pexels or pixabay.")
        };
    }

    private async Task<StockVideoSearchPage> SearchPexelsAsync(string query, int page, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(_opts.PexelsApiKey))
            throw new InvalidOperationException("Pexels API key is not configured");

        var perPage = 15;
        var url =
            $"https://api.pexels.com/videos/search?query={Uri.EscapeDataString(query)}&page={page}&per_page={perPage}";
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.Add("Authorization", _opts.PexelsApiKey);

        using var res = await http.SendAsync(req, ct);
        res.EnsureSuccessStatusCode();
        await using var stream = await res.Content.ReadAsStreamAsync(ct);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);

        var root = doc.RootElement;
        var total = root.TryGetProperty("total_results", out var t) ? t.GetInt32() : 0;
        var items = new List<StockVideoItem>();

        if (root.TryGetProperty("videos", out var videos) && videos.ValueKind == JsonValueKind.Array)
        {
            foreach (var v in videos.EnumerateArray())
            {
                var item = MapPexelsVideo(v);
                if (item != null) items.Add(item);
            }
        }

        return new StockVideoSearchPage
        {
            Items = items,
            Page = page,
            PerPage = perPage,
            TotalResults = total,
            HasMore = page * perPage < total
        };
    }

    private static StockVideoItem? MapPexelsVideo(JsonElement v)
    {
        if (!v.TryGetProperty("id", out var idEl)) return null;
        var id = idEl.GetInt32().ToString();
        var duration = v.TryGetProperty("duration", out var dEl) ? dEl.GetInt32() : (int?)null;
        var thumb = v.TryGetProperty("image", out var img) ? img.GetString() : null;
        var pageUrl = v.TryGetProperty("url", out var u) ? u.GetString() : null;
        var author = v.TryGetProperty("user", out var user) && user.TryGetProperty("name", out var n)
            ? n.GetString()
            : null;

        string? download = null;
        if (v.TryGetProperty("video_files", out var files) && files.ValueKind == JsonValueKind.Array)
        {
            string? hd = null;
            string? sd = null;
            string? any = null;
            foreach (var f in files.EnumerateArray())
            {
                if (!f.TryGetProperty("link", out var linkEl)) continue;
                var link = linkEl.GetString();
                if (string.IsNullOrEmpty(link)) continue;
                var fileType = f.TryGetProperty("file_type", out var ft) ? ft.GetString() : "";
                if (fileType != "video/mp4") continue;
                any ??= link;
                var quality = f.TryGetProperty("quality", out var q) ? q.GetString() : "";
                if (quality == "hd") hd = link;
                else if (quality == "sd") sd = link;
            }
            download = hd ?? sd ?? any;
        }

        if (string.IsNullOrEmpty(download) || string.IsNullOrEmpty(thumb)) return null;
        if (!StockVideoUrlValidator.IsAllowedVideoUrl(download) ||
            !StockVideoUrlValidator.IsAllowedImageUrl(thumb))
            return null;

        var title = !string.IsNullOrWhiteSpace(author)
            ? $"Pexels · {author}"
            : $"Pexels video {id}";

        return new StockVideoItem
        {
            Provider = "pexels",
            ExternalId = id,
            Title = title,
            Description = null,
            ThumbnailUrl = thumb,
            VideoDownloadUrl = download,
            DurationSeconds = duration > 0 ? duration : null,
            AuthorName = author,
            SourcePageUrl = pageUrl
        };
    }

    private async Task<StockVideoSearchPage> SearchPixabayAsync(string query, int page, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(_opts.PixabayApiKey))
            throw new InvalidOperationException("Pixabay API key is not configured");

        var perPage = 20;
        var url =
            $"https://pixabay.com/api/videos/?key={Uri.EscapeDataString(_opts.PixabayApiKey)}" +
            $"&q={Uri.EscapeDataString(query)}&page={page}&per_page={perPage}&video_type=all&safesearch=true";

        using var res = await http.GetAsync(url, ct);
        res.EnsureSuccessStatusCode();
        await using var stream = await res.Content.ReadAsStreamAsync(ct);
        using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);

        var root = doc.RootElement;
        var total = root.TryGetProperty("totalHits", out var t) ? t.GetInt32() : 0;
        var items = new List<StockVideoItem>();

        if (root.TryGetProperty("hits", out var hits) && hits.ValueKind == JsonValueKind.Array)
        {
            foreach (var h in hits.EnumerateArray())
            {
                var item = MapPixabayHit(h);
                if (item != null) items.Add(item);
            }
        }

        return new StockVideoSearchPage
        {
            Items = items,
            Page = page,
            PerPage = perPage,
            TotalResults = total,
            HasMore = page * perPage < total
        };
    }

    private static StockVideoItem? MapPixabayHit(JsonElement h)
    {
        if (!h.TryGetProperty("id", out var idEl)) return null;
        var id = idEl.GetInt32().ToString();
        var duration = h.TryGetProperty("duration", out var dEl) ? dEl.GetInt32() : (int?)null;
        var tags = h.TryGetProperty("tags", out var tagsEl) ? tagsEl.GetString() : "";
        var user = h.TryGetProperty("user", out var u) ? u.GetString() : null;
        var pageUrl = h.TryGetProperty("pageURL", out var p) ? p.GetString() : null;
        var pictureId = h.TryGetProperty("picture_id", out var pid) ? pid.GetString() : null;

        string? download = null;
        if (h.TryGetProperty("videos", out var videos))
        {
            download = PickPixabayVideoUrl(videos, "medium")
                     ?? PickPixabayVideoUrl(videos, "small")
                     ?? PickPixabayVideoUrl(videos, "large");
        }

        if (string.IsNullOrEmpty(download)) return null;
        if (!StockVideoUrlValidator.IsAllowedVideoUrl(download)) return null;

        var thumb = !string.IsNullOrEmpty(pictureId)
            ? $"https://i.vimeocdn.com/video/{pictureId}_295x166.jpg"
            : null;
        if (thumb == null || !StockVideoUrlValidator.IsAllowedImageUrl(thumb))
            thumb = download;

        var title = !string.IsNullOrWhiteSpace(tags)
            ? (tags.Length > 60 ? tags[..60] + "…" : tags)
            : $"Pixabay video {id}";

        return new StockVideoItem
        {
            Provider = "pixabay",
            ExternalId = id,
            Title = title,
            Description = null,
            ThumbnailUrl = thumb,
            VideoDownloadUrl = download,
            DurationSeconds = duration > 0 ? duration : null,
            AuthorName = user,
            SourcePageUrl = pageUrl
        };
    }

    private static string? PickPixabayVideoUrl(JsonElement videos, string size)
    {
        if (!videos.TryGetProperty(size, out var sizeEl)) return null;
        return sizeEl.TryGetProperty("url", out var urlEl) ? urlEl.GetString() : null;
    }

}
