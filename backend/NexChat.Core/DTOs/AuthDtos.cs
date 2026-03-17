namespace NexChat.Core.DTOs;

public record RegisterRequest(string Name, string Password, string Gender, string BirthDate);

public record LoginRequest(string Name, string Password);

public record AuthResponse(
    string Token,
    Guid UserId,
    string Name,
    string Gender,
    string UniqueCode,
    string? Avatar,
    bool IsFeatured = false,
    bool NeedsProfileContact = false
);

public record UserProfileDto(
    Guid Id,
    string Name,
    string Gender,
    string UniqueCode,
    bool IsOnline,
    string? Avatar,
    DateTime CreatedAt,
    bool IsFeatured = false,
    DateOnly? BirthDate = null,
    string? Country = null,
    string? PhoneNumber = null
);

public record UpdateAvatarRequest(string? Avatar);

public record UpdateBirthDateRequest(string BirthDate);

public record UpdateProfileContactRequest(string Country, string CountryCode, string PhoneNumber);

/// <summary>بروفايل عام لمستخدم آخر.</summary>
public record PublicProfileDto(
    Guid Id,
    string Name,
    string Gender,
    string UniqueCode,
    string? Avatar,
    bool IsFeatured = false,
    bool IsOnline = false,
    string? PhoneNumber = null,
    string? Country = null,
    bool IsContact = false
);

public record DeleteAccountRequest(string Password);

public record AddSavedCodeRequest(string Code, string? Label);
