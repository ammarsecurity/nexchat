namespace NexChat.Core.Entities;

public static class SwipeDirection
{
    public const string Like = "like";
    public const string Pass = "pass";
}

public class UserSwipe
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid FromUserId { get; set; }
    public Guid ToUserId { get; set; }
    /// <summary>"like" | "pass"</summary>
    public string Direction { get; set; } = SwipeDirection.Pass;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public User FromUser { get; set; } = null!;
    public User ToUser { get; set; } = null!;
}
