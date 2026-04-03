namespace NexChat.Core.Entities;

public class UserConversationDeletion
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid ConversationId { get; set; }
    public DateTime DeletedAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
    public Conversation Conversation { get; set; } = null!;
}
