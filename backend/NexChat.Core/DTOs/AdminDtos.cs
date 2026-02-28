namespace NexChat.Core.DTOs;

public record AdminStatsDto(
    int TotalUsers,
    int OnlineUsers,
    int ActiveSessions,
    int TotalSessionsToday,
    int TotalMessagesToday,
    int PendingReports
);

public record AdminUserDto(
    Guid Id,
    string Name,
    string Gender,
    string UniqueCode,
    bool IsOnline,
    bool IsBanned,
    DateTime CreatedAt
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

public record ChartPointDto(string Date, int Sessions, int NewUsers);

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
