namespace NexChat.API.Services;

/// <summary>
/// Apple PushKit VoIP (CallKit when app is killed). No-op until KeyPath/KeyId/TeamId
/// are set from an Apple Developer AuthKey_XXXXX.p8 (VoIP topic = BundleId.voip).
/// </summary>
public class ApnsVoipOptions
{
    public const string SectionName = "ApnsVoip";
    /// <summary>Path to AuthKey_XXXXX.p8 from Apple Developer (required to enable).</summary>
    public string? KeyPath { get; set; }
    /// <summary>Key ID (10 chars) from Apple Developer.</summary>
    public string? KeyId { get; set; }
    /// <summary>Team ID from Apple Developer membership.</summary>
    public string? TeamId { get; set; }
    /// <summary>iOS app bundle id, e.g. com.nexchat.userapp</summary>
    public string BundleId { get; set; } = "com.nexchat.userapp";
    /// <summary>Use api.sandbox.push.apple.com when true (dev builds).</summary>
    public bool UseSandbox { get; set; } = true;
}
