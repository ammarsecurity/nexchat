namespace NexChat.Core.Entities;

public class BroadcastNotificationHistory
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public string? ImageUrl { get; set; }
    public int RecipientsCount { get; set; }
    public DateTime SentAt { get; set; } = DateTime.UtcNow;
}
