namespace NexChat.Core.Entities;

public class ConversationMessage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ConversationId { get; set; }
    public Guid SenderId { get; set; }
    public string Content { get; set; } = string.Empty;
    public string Type { get; set; } = "text"; // "text" | "image" | "audio"
    public DateTime SentAt { get; set; } = DateTime.UtcNow;
    public Guid? ReplyToMessageId { get; set; }
    public bool DeletedForEveryone { get; set; } = false;
    public bool IsRead { get; set; } = false;

    public Conversation Conversation { get; set; } = null!;
    public User Sender { get; set; } = null!;
}
