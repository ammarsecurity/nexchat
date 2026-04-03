namespace NexChat.Core.Entities;

public static class MessageRequestStatus
{
    public const string Pending = "Pending";
    public const string Accepted = "Accepted";
    public const string Declined = "Declined";
}

/// <summary>طلب مراسلة من مستخدم إلى آخر قبل أن يكونا جهتي اتصال (حسب سياسة المنتج).</summary>
public class MessageRequest
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RequesterId { get; set; }
    public Guid TargetId { get; set; }
    /// <summary>Pending | Accepted | Declined</summary>
    public string Status { get; set; } = MessageRequestStatus.Pending;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? RespondedAt { get; set; }

    public User Requester { get; set; } = null!;
    public User Target { get; set; } = null!;
}
