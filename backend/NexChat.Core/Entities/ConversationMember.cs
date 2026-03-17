namespace NexChat.Core.Entities;

/// <summary>عضو في مجموعة (يُستخدم فقط عندما Conversation.Type = Group)</summary>
public class ConversationMember
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ConversationId { get; set; }
    public Guid UserId { get; set; }
    /// <summary>Admin = يمكنه إضافة/إزالة أعضاء وتعديل المجموعة</summary>
    public string Role { get; set; } = "Member"; // "Admin" | "Member"
    public DateTime JoinedAt { get; set; } = DateTime.UtcNow;

    public Conversation Conversation { get; set; } = null!;
    public User User { get; set; } = null!;
}
