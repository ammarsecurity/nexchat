namespace NexChat.Core.DTOs;

public record AddContactByPhoneRequest(string CountryCode, string PhoneNumber);

public record PhoneLookupItemDto(string Phone, string? Name = null);

public record PhoneLookupRequest(IEnumerable<PhoneLookupItemDto>? Contacts);

public record PhoneLookupMatchDto(
    Guid UserId,
    string Name,
    string? Avatar,
    string? PhoneNumber,
    string? UniqueCode,
    string? DeviceName,
    bool IsContact,
    bool HasOutgoingRequest
);

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
    string? LastMessageType,
    DateTime? LastMessageAt,
    int UnreadCount,
    bool IsPinned,
    bool IsArchived,
    bool IsGroup = false,
    bool PartnerIsOnline = false
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

/// <summary>طلب صداقة أرسله المستخدم الحالي وبانتظار الرد.</summary>
public record OutgoingMessageRequestDto(
    Guid Id,
    Guid TargetId,
    string TargetName,
    string? TargetAvatar,
    string? TargetUniqueCode,
    DateTime CreatedAt
);

/// <summary>سجل مكالمة (رسالة نوع call) لصفحة المكالمات.</summary>
public record CallHistoryItemDto(
    Guid MessageId,
    Guid ConversationId,
    Guid PartnerId,
    string PartnerName,
    string? PartnerAvatar,
    Guid CallerId,
    bool IsOutgoing,
    bool VoiceOnly,
    string Status,
    int DurationSec,
    DateTime SentAt
);
