namespace NexChat.Core;

/// <summary>WhatsApp-style disappearing messages for a conversation (new messages only).</summary>
public static class DisappearMode
{
    public const int Off = 0;
    /// <summary>Disappear once the recipient has read the message.</summary>
    public const int AfterRead = 1;
    public const int After1Hour = 2;
    public const int After24Hours = 3;
    public const int After1Week = 4;

    public static bool IsValid(int mode) =>
        mode is Off or AfterRead or After1Hour or After24Hours or After1Week;

    /// <summary>Stamp expiry at send time (timer modes). AfterRead stays null until read.</summary>
    public static DateTime? ExpiresAtOnSend(int mode, DateTime sentAt) => mode switch
    {
        After1Hour => sentAt.AddHours(1),
        After24Hours => sentAt.AddHours(24),
        After1Week => sentAt.AddDays(7),
        _ => null
    };

    /// <summary>When a message with AfterRead is marked read — short grace so the reader can view it.</summary>
    public static DateTime ExpiresAtOnRead(DateTime readAt) => readAt.AddSeconds(90);
}
