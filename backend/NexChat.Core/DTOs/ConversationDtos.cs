namespace NexChat.Core.DTOs;

public record AddContactByPhoneRequest(string CountryCode, string PhoneNumber);

public record ContactDto(
    Guid Id,
    Guid ContactUserId,
    string Name,
    string? Avatar,
    string? PhoneNumber,
    string? UniqueCode,
    DateTime CreatedAt
);

public record ConversationListItemDto(
    Guid Id,
    Guid PartnerId,
    string PartnerName,
    string? PartnerAvatar,
    string? PartnerPhone,
    string? PartnerUniqueCode,
    string? LastMessagePreview,
    DateTime? LastMessageAt,
    int UnreadCount,
    bool IsPinned,
    bool IsArchived
);

public record CreateConversationRequest(Guid ContactUserId);

public record BlockedUserDto(
    Guid Id,
    Guid BlockedUserId,
    string Name,
    string? Avatar,
    string? UniqueCode,
    DateTime CreatedAt
);
