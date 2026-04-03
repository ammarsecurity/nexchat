namespace NexChat.Core.Entities;

public class UserConversationState
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid ConversationId { get; set; }
    public DateTime? LastReadAt { get; set; }
    public bool IsPinned { get; set; } = false;
    public bool IsArchived { get; set; } = false;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
    public Conversation Conversation { get; set; } = null!;
}
