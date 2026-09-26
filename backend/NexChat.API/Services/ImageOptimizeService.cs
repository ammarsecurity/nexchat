using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Jpeg;
using SixLabors.ImageSharp.Formats.Png;
using SixLabors.ImageSharp.Formats.Webp;
using SixLabors.ImageSharp.Processing;

namespace NexChat.API.Services;

/// <summary>Resize/re-encode uploaded images and optional thumbnail copies.</summary>
public static class ImageOptimizeService
{
    public const int MaxEdge = 1600;
    public const int ThumbEdge = 256;
    public const int JpegQuality = 82;

    public sealed record OptimizedImage(byte[] Bytes, string Extension, string ContentType, byte[]? ThumbBytes);

    public static async Task<OptimizedImage?> TryOptimizeAsync(Stream input, string extension, CancellationToken ct = default)
    {
        var ext = (extension ?? "").ToLowerInvariant();
        if (ext is ".gif")
            return null; // keep animated GIFs as-is

        try
        {
            input.Position = 0;
            using var image = await Image.LoadAsync(input, ct);
            if (image.Width > MaxEdge || image.Height > MaxEdge)
            {
                image.Mutate(x => x.Resize(new ResizeOptions
                {
                    Mode = ResizeMode.Max,
                    Size = new Size(MaxEdge, MaxEdge)
                }));
            }

            byte[]? thumbBytes = null;
            if (image.Width > ThumbEdge || image.Height > ThumbEdge)
            {
                using var thumb = image.Clone(x => x.Resize(new ResizeOptions
                {
                    Mode = ResizeMode.Max,
                    Size = new Size(ThumbEdge, ThumbEdge)
                }));
                await using var thumbMs = new MemoryStream();
                await thumb.SaveAsJpegAsync(thumbMs, new JpegEncoder { Quality = 78 }, ct);
                thumbBytes = thumbMs.ToArray();
            }

            await using var ms = new MemoryStream();
            string outExt;
            string contentType;
            if (ext is ".png")
            {
                await image.SaveAsPngAsync(ms, new PngEncoder { CompressionLevel = PngCompressionLevel.BestSpeed }, ct);
                outExt = ".png";
                contentType = "image/png";
            }
            else if (ext is ".webp")
            {
                await image.SaveAsWebpAsync(ms, new WebpEncoder { Quality = JpegQuality }, ct);
                outExt = ".webp";
                contentType = "image/webp";
            }
            else
            {
                await image.SaveAsJpegAsync(ms, new JpegEncoder { Quality = JpegQuality }, ct);
                outExt = ".jpg";
                contentType = "image/jpeg";
            }

            return new OptimizedImage(ms.ToArray(), outExt, contentType, thumbBytes);
        }
        catch
        {
            return null;
        }
    }
}
