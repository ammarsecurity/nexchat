namespace NexChat.Core.Entities;

public static class StoryMediaType
{
    public const string Image = "image";
    public const string Video = "video";
    public const string Text = "text";
}

public class StorySlide
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string? MediaUrl { get; set; }
    public string MediaType { get; set; } = StoryMediaType.Image;
    public DateTime ExpiresAt { get; set; }
    public int SortOrder { get; set; }
    public string? Caption { get; set; }
    public string? OverlayJson { get; set; }
    public string? BackgroundColor { get; set; }
    public string? FilterId { get; set; }
    public int? VideoDurationSeconds { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
    public ICollection<StoryView> Views { get; set; } = new List<StoryView>();
}

public class StoryView
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid StorySlideId { get; set; }
    public Guid ViewerUserId { get; set; }
    public DateTime ViewedAt { get; set; } = DateTime.UtcNow;

    public StorySlide StorySlide { get; set; } = null!;
    public User Viewer { get; set; } = null!;
}
