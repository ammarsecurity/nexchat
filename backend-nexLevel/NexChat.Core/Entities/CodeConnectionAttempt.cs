namespace NexChat.Core.Entities;

/// <summary>
/// محاولة اتصال عبر الكود - للمراسلة المرسلة/المستلمة/الفائتة
/// </summary>
public class CodeConnectionAttempt
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RequesterId { get; set; }
    public Guid TargetId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    /// <summary>Pending, Accepted, Declined, Cancelled, TimedOut</summary>
    public string Status { get; set; } = "Pending";
    public Guid? SessionId { get; set; }

    public User Requester { get; set; } = null!;
    public User Target { get; set; } = null!;
}
