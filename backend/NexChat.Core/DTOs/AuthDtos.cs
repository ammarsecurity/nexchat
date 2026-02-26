namespace NexChat.Core.DTOs;

public record RegisterRequest(string Name, string Password, string Gender);

public record LoginRequest(string Name, string Password);

public record AuthResponse(
    string Token,
    Guid UserId,
    string Name,
    string Gender,
    string UniqueCode,
    string? Avatar
);

public record UserProfileDto(
    Guid Id,
    string Name,
    string Gender,
    string UniqueCode,
    bool IsOnline,
    string? Avatar,
    DateTime CreatedAt
);

public record UpdateAvatarRequest(string? Avatar);

public record DeleteAccountRequest(string Password);
