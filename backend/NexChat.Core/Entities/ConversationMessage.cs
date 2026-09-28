namespace NexChat.Core.Entities;

public class ConversationMessage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ConversationId { get; set; }
    public Guid SenderId { get; set; }
    public string Content { get; set; } = string.Empty;
    public string Type { get; set; } = "text"; // "text" | "image" | "audio" | "video" | "album" | "short_film" | "story_share" | "story_reply" | "call"
    public DateTime SentAt { get; set; } = DateTime.UtcNow;
    public Guid? ReplyToMessageId { get; set; }
    public bool DeletedForEveryone { get; set; } = false;
    public bool IsRead { get; set; } = false;

    /// <summary>Snapshot of conversation disappear mode at send time. See <see cref="DisappearMode"/>.</summary>
    public int DisappearMode { get; set; } = 0;
    /// <summary>UTC when clients should hide this message. Null = keep. Admin always sees the row.</summary>
    public DateTime? ExpiresAt { get; set; }

    /// <summary>WhatsApp-style view-once image/video. Recipients open once via OpenViewOnce.</summary>
    public bool IsViewOnce { get; set; }

    /// <summary>ربط رسالة محادثة ببث إعلان رسمي (للتعديل/الحذف الجماعي).</summary>
    public Guid? BroadcastId { get; set; }

    public Conversation Conversation { get; set; } = null!;
    public User Sender { get; set; } = null!;
    public ICollection<ViewOnceReceipt> ViewOnceReceipts { get; set; } = new List<ViewOnceReceipt>();
}
