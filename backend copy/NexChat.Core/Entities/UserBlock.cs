namespace NexChat.Core.Entities;

public class UserBlock
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid BlockerId { get; set; }
    public Guid BlockedUserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public User Blocker { get; set; } = null!;
    public User BlockedUser { get; set; } = null!;
}
