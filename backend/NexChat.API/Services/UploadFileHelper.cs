namespace NexChat.API.Services;

public static class UploadFileHelper
{
    /// <summary>مجلد الأفلام القصيرة تحت uploads (مثال: wwwroot/uploads/film).</summary>
    public const string ShortFilmSubfolder = "film";

    public static async Task<string> SaveUploadAsync(
        IWebHostEnvironment env,
        IConfiguration config,
        HttpRequest request,
        Stream stream,
        string originalFileName,
        string[] allowedExts,
        string defaultExt,
        string? subfolder = null)
    {
        var webRoot = env.WebRootPath ?? "wwwroot";
        var uploadsPath = string.IsNullOrWhiteSpace(subfolder)
            ? Path.Combine(webRoot, "uploads")
            : Path.Combine(webRoot, "uploads", SanitizeSubfolder(subfolder));
        Directory.CreateDirectory(uploadsPath);

        var ext = Path.GetExtension(originalFileName).ToLower();
        if (string.IsNullOrEmpty(ext) || !allowedExts.Contains(ext))
            ext = defaultExt;
        var fileName = $"{Guid.NewGuid()}{ext}";
        var filePath = Path.Combine(uploadsPath, fileName);

        stream.Position = 0;
        await using (var dest = new FileStream(filePath, FileMode.Create))
            await stream.CopyToAsync(dest);

        var urlPath = string.IsNullOrWhiteSpace(subfolder)
            ? $"uploads/{fileName}"
            : $"uploads/{SanitizeSubfolder(subfolder)}/{fileName}";

        var baseUrl = config["Media:BaseUrl"];
        return !string.IsNullOrEmpty(baseUrl)
            ? $"{baseUrl.TrimEnd('/')}/{urlPath}"
            : $"{request.Scheme}://{request.Host}/{urlPath}";
    }

    public static void TryDeleteUploadFile(IWebHostEnvironment env, string? mediaUrl)
    {
        if (string.IsNullOrWhiteSpace(mediaUrl)) return;
        try
        {
            var webRoot = env.WebRootPath ?? "wwwroot";
            var pathPart = Uri.TryCreate(mediaUrl, UriKind.Absolute, out var uri)
                ? uri.AbsolutePath
                : mediaUrl;
            pathPart = pathPart.Trim().TrimStart('/').Replace('\\', '/');

            string? relative = null;
            if (pathPart.StartsWith("uploads/", StringComparison.OrdinalIgnoreCase))
                relative = pathPart;
            else
            {
                var fileName = Path.GetFileName(pathPart);
                if (!string.IsNullOrEmpty(fileName) && !fileName.Contains(".."))
                    relative = $"uploads/{fileName}";
            }

            if (string.IsNullOrEmpty(relative) || relative.Contains("..")) return;

            var fullPath = Path.Combine(webRoot, relative.Replace('/', Path.DirectorySeparatorChar));
            if (File.Exists(fullPath))
                File.Delete(fullPath);
        }
        catch
        {
            // ignore
        }
    }

    private static string SanitizeSubfolder(string subfolder)
    {
        var parts = subfolder.Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries);
        return string.Join(Path.DirectorySeparatorChar, parts.Where(p => p != "." && p != ".."));
    }
}
