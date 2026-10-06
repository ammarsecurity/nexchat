namespace NexChat.Core.Entities;

public class ShortFilmLike
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ShortFilmId { get; set; }
    public Guid UserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public ShortFilm ShortFilm { get; set; } = null!;
    public User User { get; set; } = null!;
}

public class ShortFilmWatchLater
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ShortFilmId { get; set; }
    public Guid UserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public ShortFilm ShortFilm { get; set; } = null!;
    public User User { get; set; } = null!;
}

public class ShortFilmReaction
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ShortFilmId { get; set; }
    public Guid UserId { get; set; }
    public string Emoji { get; set; } = "❤️";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public ShortFilm ShortFilm { get; set; } = null!;
    public User User { get; set; } = null!;
}

public class ShortFilmSeriesFollow
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid SeriesId { get; set; }
    public Guid UserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public ShortFilmSeries Series { get; set; } = null!;
    public User User { get; set; } = null!;
}

/// <summary>Top-level short-film comment (no nested threads in v1).</summary>
public class ShortFilmComment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ShortFilmId { get; set; }
    public Guid UserId { get; set; }
    public string Body { get; set; } = "";
    public bool IsHidden { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public ShortFilm ShortFilm { get; set; } = null!;
    public User User { get; set; } = null!;
    public ICollection<ShortFilmCommentReport> Reports { get; set; } = new List<ShortFilmCommentReport>();
}

public class ShortFilmCommentReport
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CommentId { get; set; }
    public Guid ReporterId { get; set; }
    public string Reason { get; set; } = "";
    public bool IsReviewed { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public ShortFilmComment Comment { get; set; } = null!;
    public User Reporter { get; set; } = null!;
}
