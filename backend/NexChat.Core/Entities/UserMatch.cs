namespace NexChat.Core.Entities;

public class UserMatch
{
    public Guid Id { get; set; } = Guid.NewGuid();
    /// <summary>Smaller Guid of the pair (canonical order).</summary>
    public Guid UserAId { get; set; }
    /// <summary>Larger Guid of the pair (canonical order).</summary>
    public Guid UserBId { get; set; }
    public Guid ConversationId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public User UserA { get; set; } = null!;
    public User UserB { get; set; } = null!;
    public Conversation Conversation { get; set; } = null!;
}
