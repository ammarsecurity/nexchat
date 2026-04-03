namespace NexChat.Core.Entities;

/// <summary>0 = محادثة ثنائية، 1 = مجموعة</summary>
public static class ConversationType
{
    public const int Private = 0;
    public const int Group = 1;
}

public class Conversation
{
    public Guid Id { get; set; } = Guid.NewGuid();
    /// <summary>0 = Private (ثنائي)، 1 = Group (مجموعة)</summary>
    public int Type { get; set; } = ConversationType.Private;
    /// <summary>للمحادثة الثنائية: الطرف الأول. للمجموعة: غير مستخدم أو منشئ المجموعة.</summary>
    public Guid? User1Id { get; set; }
    /// <summary>للمحادثة الثنائية: الطرف الثاني. للمجموعة: غير مستخدم.</summary>
    public Guid? User2Id { get; set; }
    /// <summary>اسم المجموعة (للمجموعات فقط)</summary>
    public string? Name { get; set; }
    /// <summary>صورة المجموعة (للمجموعات فقط)</summary>
    public string? ImageUrl { get; set; }
    /// <summary>منشئ المجموعة (للمجموعات فقط)</summary>
    public Guid? CreatedById { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public User? User1 { get; set; }
    public User? User2 { get; set; }
    public User? CreatedBy { get; set; }
    public ICollection<ConversationMessage> Messages { get; set; } = new List<ConversationMessage>();
    public ICollection<ConversationMember> Members { get; set; } = new List<ConversationMember>();
}
