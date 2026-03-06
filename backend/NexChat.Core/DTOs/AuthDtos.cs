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
    bool IsFeatured = false
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
    DateOnly? BirthDate = null
);

public record UpdateAvatarRequest(string? Avatar);

public record UpdateBirthDateRequest(string BirthDate);

public record DeleteAccountRequest(string Password);

public record AddSavedCodeRequest(string Code, string? Label);
