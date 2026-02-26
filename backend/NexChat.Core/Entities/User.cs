namespace NexChat.Core.Entities;

public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public string Gender { get; set; } = string.Empty; // "male" | "female" | "other"
    public string UniqueCode { get; set; } = string.Empty;
    public bool IsOnline { get; set; } = false;
    public bool IsBanned { get; set; } = false;
    public bool IsAdmin { get; set; } = false;
    public string? Avatar { get; set; } = null;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<ChatSession> SessionsAsUser1 { get; set; } = new List<ChatSession>();
    public ICollection<ChatSession> SessionsAsUser2 { get; set; } = new List<ChatSession>();
    public ICollection<Report> ReportsGiven { get; set; } = new List<Report>();
    public ICollection<Report> ReportsReceived { get; set; } = new List<Report>();
}
