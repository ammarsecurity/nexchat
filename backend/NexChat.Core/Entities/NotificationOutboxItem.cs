namespace NexChat.Core.Entities;

public static class NotificationOutboxStatus
{
    public const string Pending = "Pending";
    public const string Processing = "Processing";
    public const string Sent = "Sent";
    public const string Failed = "Failed";
    public const string DeadLetter = "DeadLetter";
}

public class NotificationOutboxItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Type { get; set; } = string.Empty;
    public Guid RecipientUserId { get; set; }
    public string PayloadJson { get; set; } = "{}";
    public string Status { get; set; } = NotificationOutboxStatus.Pending;
    public int AttemptCount { get; set; } = 0;
    public DateTime NextAttemptAt { get; set; } = DateTime.UtcNow;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastAttemptAt { get; set; }
    public string? LastError { get; set; }
    public string? LastProviderMessageId { get; set; }
}
