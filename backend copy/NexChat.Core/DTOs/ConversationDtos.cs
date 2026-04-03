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
    bool IsArchived,
    bool IsGroup = false
);

public record CreateConversationRequest(Guid ContactUserId);

public record CreateGroupRequest(string Name, string? ImageUrl, List<Guid> MemberUserIds);

/// <summary>تعديل اسم أو صورة المجموعة (للمدير). يمكن إرسال أحدهما أو كليهما.</summary>
public record UpdateGroupRequest(string? Name, string? ImageUrl);

public record GroupMemberDto(Guid UserId, string Name, string? Avatar, string Role, DateTime JoinedAt);

public record BlockedUserDto(
    Guid Id,
    Guid BlockedUserId,
    string Name,
    string? Avatar,
    string? UniqueCode,
    DateTime CreatedAt
);

public record CreateMessageRequestDto(Guid TargetUserId);

public record MessageRequestListItemDto(
    Guid Id,
    Guid RequesterId,
    string RequesterName,
    string? RequesterAvatar,
    string? RequesterUniqueCode,
    DateTime CreatedAt
);
