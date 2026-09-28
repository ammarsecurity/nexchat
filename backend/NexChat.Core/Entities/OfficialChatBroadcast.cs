namespace NexChat.Core.Entities;

/// <summary>سجل بث رسالة رسمية من حساب NexChat إلى كل المستخدمين.</summary>
public class OfficialChatBroadcast
{
    public Guid Id { get; set; } = Guid.NewGuid();
    /// <summary>نص أو رابط الوسائط (نص واضح للأدمن).</summary>
    public string Content { get; set; } = string.Empty;
    /// <summary>text | image | video</summary>
    public string Type { get; set; } = "text";
    /// <summary>تعليق اختياري مع صورة/فيديو — يُرسل كرسالة نص منفصلة إن وُجد.</summary>
    public string? Caption { get; set; }
    public int RecipientsCount { get; set; }
    public DateTime SentAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }
}
