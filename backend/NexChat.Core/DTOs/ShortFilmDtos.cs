namespace NexChat.Core.DTOs;

public record ShortFilmDto(
    Guid Id,
    string Title,
    string? Description,
    string VideoUrl,
    string? ThumbnailUrl,
    int? DurationSeconds,
    Guid? SectionId,
    string? SectionName,
    int SortOrder,
    bool IsFeatured,
    int ViewCount,
    DateTime CreatedAt);

public record ShortFilmSectionDto(
    Guid Id,
    string Name,
    int SortOrder,
    int FilmCount,
    string? ImageUrl);

public record ShortFilmSectionBrowseDto(
    Guid Id,
    string Name,
    int SortOrder,
    string? ImageUrl,
    IReadOnlyList<ShortFilmDto> Films);

public record ShortFilmsPageDto(
    IReadOnlyList<ShortFilmDto> Items,
    int Total,
    int Page,
    int PageSize,
    bool HasMore);

public record ShortFilmsBrowseDto(
    IReadOnlyList<ShortFilmSectionBrowseDto> Sections,
    IReadOnlyList<ShortFilmDto> UncategorizedFilms);

public record AdminShortFilmDto(
    Guid Id,
    string Title,
    string? Description,
    string VideoUrl,
    string? ThumbnailUrl,
    int? DurationSeconds,
    Guid? SectionId,
    string? SectionName,
    int SortOrder,
    bool IsActive,
    bool IsFeatured,
    int ViewCount,
    Guid? CreatedByAdminId,
    DateTime CreatedAt,
    DateTime UpdatedAt);

public record AdminShortFilmSectionDto(
    Guid Id,
    string Name,
    int SortOrder,
    bool IsActive,
    int FilmCount,
    string? ImageUrl,
    DateTime CreatedAt,
    DateTime UpdatedAt);

public record CreateShortFilmSectionDto(string Name, int SortOrder, bool IsActive, string? ImageUrl);

public record UpdateShortFilmSectionDto(string? Name, int? SortOrder, bool? IsActive, string? ImageUrl, bool? ClearImageUrl);

public record CreateShortFilmDto(
    string Title,
    string? Description,
    string VideoUrl,
    string? ThumbnailUrl,
    int? DurationSeconds,
    Guid? SectionId,
    int SortOrder,
    bool IsActive,
    bool IsFeatured);

public record UpdateShortFilmDto(
    string? Title,
    string? Description,
    string? VideoUrl,
    string? ThumbnailUrl,
    int? DurationSeconds,
    Guid? SectionId,
    bool? SetSectionId,
    int? SortOrder,
    bool? IsActive,
    bool? IsFeatured);

public record StockVideoProvidersDto(IReadOnlyList<string> Providers);

public record StockVideoSearchItemDto(
    string Provider,
    string ExternalId,
    string Title,
    string? Description,
    string ThumbnailUrl,
    string VideoDownloadUrl,
    int? DurationSeconds,
    string? AuthorName,
    string? SourcePageUrl);

public record StockVideoSearchResultDto(
    IReadOnlyList<StockVideoSearchItemDto> Items,
    int Page,
    int PerPage,
    int TotalResults,
    bool HasMore);

public record ImportStockVideoDto(
    string Provider,
    string ExternalId,
    string Title,
    string? Description,
    string VideoDownloadUrl,
    string? ThumbnailUrl,
    int? DurationSeconds,
    Guid? SectionId,
    int SortOrder,
    bool IsActive,
    bool IsFeatured);
