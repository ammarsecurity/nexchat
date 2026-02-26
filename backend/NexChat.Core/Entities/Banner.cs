namespace NexChat.Core.Entities;

public class Banner
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string ImageUrl { get; set; } = string.Empty;
    public string Placement { get; set; } = string.Empty; // "home" | "matching"
    public int Order { get; set; }
    public bool IsActive { get; set; } = true;
    public string? Link { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
