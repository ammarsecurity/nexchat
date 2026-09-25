namespace NexChat.Core.DTOs;

public class EvolutionWhatsAppConfigDto
{
    public bool Enabled { get; set; }
    public string BaseUrl { get; set; } = "";
    public string ApiKey { get; set; } = "";
    public string InstanceName { get; set; } = "";
    public string MessageTemplate { get; set; } =
        "اسم الدخول: {name}\nرمز التحقق في NexChat هو: {code}\nصالح لمدة {minutes} دقائق. لا تشاركه مع أحد.";
    public int OtpExpiryMinutes { get; set; } = 5;
    public int OtpLength { get; set; } = 6;
}

public record EvolutionWhatsAppStatusDto(bool Enabled, bool Configured);

public record SendOtpRequest(
    string Purpose,
    string CountryCode,
    string PhoneNumber,
    string? Country = null
);

public record VerifyPhoneOtpRequest(
    string CountryCode,
    string PhoneNumber,
    string Country,
    string Code
);

public record ResetPasswordOtpRequest(
    string CountryCode,
    string PhoneNumber,
    string Code,
    string NewPassword
);

public record SendOtpResponse(bool Sent, int ExpiresInSeconds, string? Message = null);

public record EvolutionTestMessageRequest(string CountryCode, string PhoneNumber);
