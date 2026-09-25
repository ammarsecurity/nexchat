namespace NexChat.Core.Entities;

/// <summary>تحدي OTP عبر واتساب (Evolution API).</summary>
public class OtpChallenge
{
    public Guid Id { get; set; } = Guid.NewGuid();
    /// <summary>الرقم الكامل بأرقام فقط (مثل 9647712345678).</summary>
    public string PhoneNumber { get; set; } = string.Empty;
    /// <summary>verify_phone | reset_password</summary>
    public string Purpose { get; set; } = string.Empty;
    public string CodeHash { get; set; } = string.Empty;
    public Guid? UserId { get; set; }
    /// <summary>كود الدولة ISO-2 عند تعيين الهاتف.</summary>
    public string? PendingCountry { get; set; }
    public int Attempts { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public bool Consumed { get; set; }
}
