namespace NexChat.Core.Entities;

/// <summary>رد فعل مستخدم على رسالة (إيموجي واحد لكل مستخدم لكل رسالة).</summary>
public class MessageReaction
{
    public Guid MessageId { get; set; }
    public Guid UserId { get; set; }
    public string Emoji { get; set; } = string.Empty; // e.g. "❤️", "👍"

    public ConversationMessage Message { get; set; } = null!;
    public User User { get; set; } = null!;
}
