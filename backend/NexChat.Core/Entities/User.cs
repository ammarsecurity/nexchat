namespace NexChat.Core.Entities;

public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string Gender { get; set; } = string.Empty; // "male" | "female" | "other"
    public DateOnly? BirthDate { get; set; }
    public string UniqueCode { get; set; } = string.Empty;
    public bool IsOnline { get; set; } = false;
    /// <summary>إذا كان false يُعرض للآخرين كغير متصل حتى لو كان IsOnline true.</summary>
    public bool ShowOnlineStatusToOthers { get; set; } = true;
    public bool IsBanned { get; set; } = false;
    public bool IsAdmin { get; set; } = false;
    public bool IsFeatured { get; set; } = false;
    public string? Avatar { get; set; } = null;
    /// <summary>كود الدولة ISO 2 (مثل IQ, SA)</summary>
    public string? Country { get; set; } = null;
    /// <summary>رقم الهاتف مع مفتاح الدولة (مثل 9647712345678)</summary>
    public string? PhoneNumber { get; set; } = null;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<ChatSession> SessionsAsUser1 { get; set; } = new List<ChatSession>();
    public ICollection<ChatSession> SessionsAsUser2 { get; set; } = new List<ChatSession>();
    public ICollection<Report> ReportsGiven { get; set; } = new List<Report>();
    public ICollection<Report> ReportsReceived { get; set; } = new List<Report>();
}
