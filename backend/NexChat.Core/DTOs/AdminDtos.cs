namespace NexChat.Core.DTOs;

public record AdminStatsDto(
    int TotalUsers,
    int OnlineUsers,
    int ActiveSessions,
    int TotalSessionsToday,
    int TotalMessagesToday,
    int PendingReports,
    int TotalConversations,
    int TotalConversationMessagesToday,
    int TotalContacts,
    int TotalBlocks
);

public record AdminUserDto(
    Guid Id,
    string Name,
    string Gender,
    string UniqueCode,
    bool IsOnline,
    bool IsBanned,
    bool IsFeatured,
    DateTime CreatedAt,
    DateOnly? BirthDate,
    string? PhoneNumber
);

public record AdminSessionDto(
    Guid Id,
    string User1Name,
    string User2Name,
    string Type,
    DateTime StartedAt,
    DateTime? EndedAt,
    int MessageCount
);

public record AdminReportDto(
    Guid Id,
    string ReporterName,
    string ReportedName,
    string Reason,
    bool IsReviewed,
    DateTime CreatedAt
);

public record PagedResult<T>(IEnumerable<T> Items, int Total, int Page, int PageSize);

public record ChartPointDto(string Date, int Sessions, int NewUsers, int Conversations, int NewContacts);

public record AdminMessageDto(
    Guid Id,
    string SenderName,
    string SessionId,
    string Content,
    string Type,
    DateTime SentAt
);

public record BannerDto(
    Guid Id,
    string ImageUrl,
    string Placement,
    int Order,
    bool IsActive,
    string? Link,
    DateTime CreatedAt
);

public record CreateBannerDto(string ImageUrl, string Placement, int Order, bool IsActive, string? Link);

public record UpdateBannerDto(string? ImageUrl, string? Placement, int? Order, bool? IsActive, string? Link);

public record ReorderBannersDto(IEnumerable<Guid> Ids);

public record UpdateSiteContentDto(string Content);

public record SupportSendDto(Guid SessionId, string Content);

public record UpdateSupportAvatarDto(string? Avatar);

public record BroadcastNotificationDto(string Title, string Body, string? ImageUrl);
public record AdminBroadcastNotificationDto(Guid Id, string Title, string Body, string? ImageUrl, int RecipientsCount, DateTime SentAt);

public record SetFeaturedRequest(bool Featured);

public record DeleteUsersRequest(IEnumerable<Guid> Ids);

public record AdminConversationDto(Guid Id, string User1Name, string User2Name, DateTime CreatedAt, int MessageCount, DateTime? LastMessageAt);
public record AdminConversationMessageDto(Guid Id, string SenderName, string Content, string Type, DateTime SentAt);
public record AdminBlockDto(Guid Id, string BlockerName, string BlockedUserName, DateTime CreatedAt);
public record AdminContactDto(Guid Id, string UserName, string ContactUserName, DateTime CreatedAt);

public record DeleteConversationsRequest(IEnumerable<Guid> Ids);
public record DeleteMessagesRequest(IEnumerable<Guid> Ids);
public record DeleteSessionsRequest(IEnumerable<Guid> Ids);
