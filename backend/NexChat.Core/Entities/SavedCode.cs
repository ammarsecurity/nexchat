namespace NexChat.Core.Entities;

/// <summary>
/// أكواد محفوظة للحسابات المميزة (يمكنهم إضافتها للاتصال السريع).
/// </summary>
public class SavedCode
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Code { get; set; } = string.Empty; // NX-XXXX
    public string? Label { get; set; } // اسم اختياري
    public DateTime AddedAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
}
