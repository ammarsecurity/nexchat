namespace NexChat.Core.Entities;

/// <summary>Tracks which bundled discover-bot photo file is bound to which bot user.</summary>
public class DiscoverBotPhotoUsage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    /// <summary>Path relative to photo root, e.g. female/f-001.jpg</summary>
    public string RelativePath { get; set; } = string.Empty;
    public string Gender { get; set; } = string.Empty;
    public Guid UserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
}
