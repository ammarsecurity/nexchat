namespace NexChat.Core.DTOs;

public class DiscoverBotsConfigDto
{
    public bool Enabled { get; set; } = true;
    public int FemaleTarget { get; set; } = 100;
    public int MaleTarget { get; set; } = 100;
    public int MatchPercent { get; set; } = 30;
    public int AgeMin { get; set; } = 18;
    public int AgeMax { get; set; } = 45;
    public string Country { get; set; } = "IQ";
}

public record DiscoverBotsStatusDto(
    DiscoverBotsConfigDto Config,
    int FemaleBots,
    int MaleBots,
    int FemalePhotosAvailable,
    int MalePhotosAvailable,
    int FemalePhotosUsed,
    int MalePhotosUsed);

public record DiscoverBotsSyncResultDto(
    int CreatedFemale,
    int CreatedMale,
    int FemalePhotosRemaining,
    int MalePhotosRemaining,
    string? Message);
