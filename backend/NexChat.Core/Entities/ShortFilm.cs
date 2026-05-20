namespace NexChat.Core.Entities;

public class ShortFilm
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "";
    public string? Description { get; set; }
    /// <summary>مصدر الاستيراد (pexels / pixabay) — للتتبع فقط.</summary>
    public string? StockProvider { get; set; }
    public string? StockExternalId { get; set; }
    public string VideoUrl { get; set; } = "";
    public string? ThumbnailUrl { get; set; }
    public int? DurationSeconds { get; set; }
    public Guid? SectionId { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
    public bool IsFeatured { get; set; }
    public int ViewCount { get; set; }
    public Guid? CreatedByAdminId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public ShortFilmSection? Section { get; set; }
    public User? CreatedByAdmin { get; set; }
}
