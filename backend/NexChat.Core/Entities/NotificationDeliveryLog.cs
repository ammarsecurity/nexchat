namespace NexChat.Core.Entities;

public class NotificationDeliveryLog
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Channel { get; set; } = "push";
    public string Type { get; set; } = string.Empty;
    public Guid? RecipientUserId { get; set; }
    public string? RecipientSubscriptionId { get; set; }
    public bool Success { get; set; }
    public int? HttpStatusCode { get; set; }
    public int Attempt { get; set; } = 1;
    public string? ProviderMessageId { get; set; }
    public string? Error { get; set; }
    public string? PayloadPreview { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
