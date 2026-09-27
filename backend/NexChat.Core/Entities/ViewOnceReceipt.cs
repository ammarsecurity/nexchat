namespace NexChat.Core.Entities;

/// <summary>Per-user open receipt for WhatsApp-style view-once media.</summary>
public class ViewOnceReceipt
{
    public Guid MessageId { get; set; }
    public Guid UserId { get; set; }
    public DateTime ViewedAt { get; set; } = DateTime.UtcNow;

    public ConversationMessage Message { get; set; } = null!;
    public User User { get; set; } = null!;
}
