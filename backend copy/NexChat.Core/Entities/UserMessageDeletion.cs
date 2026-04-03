namespace NexChat.Core.Entities;

public class UserMessageDeletion
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid MessageId { get; set; }
    public DateTime DeletedAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
    public ConversationMessage Message { get; set; } = null!;
}
