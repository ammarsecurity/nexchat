namespace NexChat.Core.Entities;

public class Message
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid SessionId { get; set; }
    public Guid SenderId { get; set; }
    public string Content { get; set; } = string.Empty;
    public string Type { get; set; } = "text"; // "text" | "system"
    public DateTime SentAt { get; set; } = DateTime.UtcNow;

    public ChatSession Session { get; set; } = null!;
    public User Sender { get; set; } = null!;
}
