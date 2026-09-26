namespace NexChat.Core.DTOs;

public record StoryRingDto(
    Guid UserId,
    string Name,
    string? Avatar,
    bool HasUnseen,
    string? LatestThumbUrl,
    DateTime? LatestAt,
    int SlideCount,
    bool IsMine
);

public record StorySlideDto(
    Guid Id,
    Guid UserId,
    string? MediaUrl,
    string MediaType,
    string? Caption,
    string? OverlayJson,
    string? BackgroundColor,
    string? FilterId,
    int? VideoDurationSeconds,
    int SortOrder,
    DateTime CreatedAt,
    DateTime ExpiresAt,
    bool ViewedByMe,
    int ViewCount,
    bool LikedByMe,
    int LikeCount
);

public record CreateStorySlideRequest(
    string? MediaUrl,
    string MediaType,
    string? Caption,
    string? OverlayJson,
    string? BackgroundColor,
    string? FilterId,
    int? VideoDurationSeconds,
    int? SortOrder
);

public record UpdateStorySlideRequest(
    string? MediaUrl,
    string? Caption,
    string? OverlayJson,
    string? BackgroundColor,
    string? FilterId,
    int? VideoDurationSeconds
);

public record StoryViewerDto(
    Guid UserId,
    string Name,
    string? Avatar,
    DateTime? ViewedAt,
    bool Liked
);

public record StoryReplyRequest(string Text);

public record StoryReplyResponse(Guid ConversationId, Guid MessageId);

public record StoryLikeResponse(bool Liked, int LikeCount);
