namespace NexChat.Core.Entities;

public class Report
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ReporterId { get; set; }
    public Guid ReportedId { get; set; }
    public string Reason { get; set; } = string.Empty;
    public bool IsReviewed { get; set; } = false;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public User Reporter { get; set; } = null!;
    public User Reported { get; set; } = null!;
}
