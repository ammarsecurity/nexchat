namespace NexChat.Core.Entities;

/// <summary>A bounded viewing session, not a reusable public media URL.</summary>
public class ViewOnceMediaSession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid MessageId { get; set; }
    public Guid UserId { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime? ClosedAt { get; set; }
    public ConversationMessage Message { get; set; } = null!;
}
