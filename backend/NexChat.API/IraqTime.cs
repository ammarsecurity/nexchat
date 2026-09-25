namespace NexChat.API.Controllers;

/// <summary>Asia/Baghdad fixed UTC+3 (Iraq has no DST). Storage remains UTC.</summary>
public static class IraqTime
{
    public static readonly TimeSpan Offset = TimeSpan.FromHours(3);

    /// <summary>Current wall-clock in Iraq (Unspecified).</summary>
    public static DateTime Now => DateTime.UtcNow.Add(Offset);

    /// <summary>
    /// Start of the current Iraqi calendar day as a UTC instant
    /// (for comparing against UTC columns like SentAt / StartedAt).
    /// </summary>
    public static DateTime TodayUtcStart
    {
        get
        {
            var iraq = Now;
            var midnightIraq = new DateTime(iraq.Year, iraq.Month, iraq.Day, 0, 0, 0, DateTimeKind.Unspecified);
            return DateTime.SpecifyKind(midnightIraq - Offset, DateTimeKind.Utc);
        }
    }
}
