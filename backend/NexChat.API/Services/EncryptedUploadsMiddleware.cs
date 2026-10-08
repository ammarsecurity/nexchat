using System.Text.RegularExpressions;
using Microsoft.AspNetCore.StaticFiles;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

/// <summary>
/// Serves /uploads/* with on-the-fly decryption so app + admin keep using the same public URLs.
/// Legacy plaintext files pass through unchanged.
/// </summary>
public sealed partial class EncryptedUploadsMiddleware(
    RequestDelegate next,
    IWebHostEnvironment env,
    IMediaFileCrypto crypto,
    ILogger<EncryptedUploadsMiddleware> logger)
{
    private static readonly FileExtensionContentTypeProvider Types = new();

    [GeneratedRegex(@"^/uploads/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?:_thumb)?\.[A-Za-z0-9]+)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex UploadPath();

    public async Task InvokeAsync(HttpContext context)
    {
        if (!HttpMethods.IsGet(context.Request.Method) && !HttpMethods.IsHead(context.Request.Method))
        {
            await next(context);
            return;
        }

        var path = context.Request.Path.Value ?? "";
        var match = UploadPath().Match(path);
        if (!match.Success)
        {
            await next(context);
            return;
        }

        var fileName = match.Groups[1].Value;
        var root = Path.GetFullPath(Path.Combine(env.WebRootPath ?? Path.Combine(env.ContentRootPath, "wwwroot"), "uploads"));
        var fullPath = Path.GetFullPath(Path.Combine(root, fileName));
        if (!fullPath.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) &&
            !fullPath.Equals(root, StringComparison.OrdinalIgnoreCase))
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            return;
        }

        if (!File.Exists(fullPath))
        {
            await next(context);
            return;
        }

        if (!Types.TryGetContentType(fileName, out var contentType))
            contentType = "application/octet-stream";

        byte[] payload;
        try
        {
            payload = await crypto.ReadAllDecryptedAsync(fullPath, context.RequestAborted);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to read upload {File}", fileName);
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            return;
        }

        // Flutter web (and admin) load media cross-origin; reflecting Origin matches NexChatPolicy.
        ApplyCors(context);

        context.Response.ContentType = contentType;
        context.Response.Headers.CacheControl = "private, max-age=3600";
        context.Response.Headers["X-Content-Type-Options"] = "nosniff";
        context.Response.ContentLength = payload.Length;

        if (HttpMethods.IsHead(context.Request.Method))
            return;

        await context.Response.Body.WriteAsync(payload, context.RequestAborted);
    }

    private static void ApplyCors(HttpContext context)
    {
        var origin = context.Request.Headers.Origin.ToString();
        if (string.IsNullOrEmpty(origin)) return;
        context.Response.Headers.Append("Access-Control-Allow-Origin", origin);
        context.Response.Headers.Append("Access-Control-Allow-Credentials", "true");
        context.Response.Headers.Append("Vary", "Origin");
        var requestHeaders = context.Request.Headers.AccessControlRequestHeaders.ToString();
        if (!string.IsNullOrEmpty(requestHeaders))
            context.Response.Headers.Append("Access-Control-Allow-Headers", requestHeaders);
    }
}

public static class EncryptedUploadsMiddlewareExtensions
{
    public static IApplicationBuilder UseEncryptedUploads(this IApplicationBuilder app) =>
        app.UseMiddleware<EncryptedUploadsMiddleware>();
}
