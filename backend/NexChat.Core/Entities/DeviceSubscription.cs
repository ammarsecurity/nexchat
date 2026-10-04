namespace NexChat.Core.Entities;

public class DeviceSubscription
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    /// <summary>Stable app installation UUID shared by OneSignal and PushKit.</summary>
    public string? InstallationId { get; set; }
    public string OneSignalPlayerId { get; set; } = string.Empty;
    /// <summary>iOS PushKit VoIP device token (hex). Used for CallKit when app is killed.</summary>
    public string? VoipDeviceToken { get; set; }
    public string? Platform { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public User User { get; set; } = null!;
}
