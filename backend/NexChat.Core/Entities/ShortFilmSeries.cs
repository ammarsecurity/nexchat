namespace NexChat.Core.Entities;

public class ShortFilmSeries
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "";
    public string? Description { get; set; }
    public string? CoverUrl { get; set; }
    public Guid? SectionId { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
    public bool IsFeatured { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public ShortFilmSection? Section { get; set; }
    public ICollection<ShortFilm> Episodes { get; set; } = new List<ShortFilm>();
}
