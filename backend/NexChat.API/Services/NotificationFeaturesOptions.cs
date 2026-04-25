namespace NexChat.API.Services;

public class NotificationFeaturesOptions
{
    public bool OutboxEnabled { get; set; } = true;
    public bool ServerNotificationCenterEnabled { get; set; } = true;
}
