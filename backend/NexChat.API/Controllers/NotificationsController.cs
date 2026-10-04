using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class NotificationsController(AppDbContext db) : ControllerBase
{
    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterDeviceRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.PlayerId) || req.PlayerId.Length > 64 ||
            req.PlayerId.StartsWith("voip:") || req.PlayerId.StartsWith("installation:"))
            return BadRequest(new { message = "Invalid playerId" });
        if (!TryInstallation(req.InstallationId, out var installationId))
            return BadRequest(new { message = "Invalid installationId" });
        if (!Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId))
            return Unauthorized();

        return await Upsert(userId, installationId, req.PlayerId.Trim(), null, req.Platform);
    }

    /// <summary>Both push channels belong to the same installation, never the user's newest phone.</summary>
    [HttpPost("voip-token")]
    public async Task<IActionResult> RegisterVoip([FromBody] RegisterVoipRequest req)
    {
        if (!TryInstallation(req.InstallationId, out var installationId) || installationId == null)
            return BadRequest(new { message = "installationId is required for VoIP registration" });
        // Empty token is an explicit PushKit invalidation, not a new registration.
        var token = req.Token?.Trim().ToLowerInvariant() ?? "";
        if (token.Length > 200 || token.Any(c => !Uri.IsHexDigit(c)))
            return BadRequest(new { message = "Invalid VoIP token" });
        if (!Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId))
            return Unauthorized();
        if (token.Length == 0)
        {
            await db.DeviceSubscriptions.Where(d => d.UserId == userId && d.InstallationId == installationId)
                .ExecuteUpdateAsync(s => s.SetProperty(d => d.VoipDeviceToken, (string?)null));
            return Ok();
        }
        return await Upsert(userId, installationId, null, token, "ios");
    }

    private async Task<IActionResult> Upsert(Guid userId, string? installationId, string? playerId,
        string? voipToken, string? platform)
    {
        // Transfer ownership and merge legacy split rows in one transaction. Unique indexes
        // prevent concurrent account registrations from reintroducing duplicate token owners.
        await using var transaction = await db.Database.BeginTransactionAsync();
        try
        {
            var matches = await db.DeviceSubscriptions.Where(d =>
                (installationId != null && d.InstallationId == installationId) ||
                (playerId != null && d.OneSignalPlayerId == playerId) ||
                (voipToken != null && d.VoipDeviceToken == voipToken)).ToListAsync();
            var row = matches.FirstOrDefault(d => installationId != null && d.InstallationId == installationId)
                ?? matches.FirstOrDefault();
            if (row == null)
            {
                row = new DeviceSubscription
                {
                    OneSignalPlayerId = playerId ?? $"installation:{installationId}",
                };
                db.DeviceSubscriptions.Add(row);
            }
            else
            {
                var duplicates = matches.Where(d => d.Id != row.Id).ToList();
                db.DeviceSubscriptions.RemoveRange(duplicates);
                // Free unique token values before assigning them to the retained row.
                await db.SaveChangesAsync();
                // A legacy row is token-scoped; don't copy a second token across devices.
                if (row.InstallationId != installationId || installationId == null)
                {
                    if (voipToken == null) row.VoipDeviceToken = null;
                    if (playerId == null) row.OneSignalPlayerId = $"installation:{installationId}";
                }
            }
            row.UserId = userId;
            row.InstallationId = installationId;
            row.OneSignalPlayerId = playerId ?? row.OneSignalPlayerId;
            row.VoipDeviceToken = voipToken ?? row.VoipDeviceToken;
            row.Platform = platform?.Trim().ToLowerInvariant() is { } value ? value[..Math.Min(20, value.Length)] : null;
            row.CreatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync();
            await transaction.CommitAsync();
            return Ok();
        }
        catch (DbUpdateException)
        {
            await transaction.RollbackAsync();
            return Conflict(new { message = "Device registration changed concurrently; retry registration." });
        }
    }

    [HttpPost("unregister")]
    public async Task<IActionResult> Unregister([FromBody] RegisterDeviceRequest req)
    {
        if (!TryInstallation(req.InstallationId, out var installationId) ||
            (installationId == null && string.IsNullOrWhiteSpace(req.PlayerId)))
            return BadRequest(new { message = "installationId or playerId is required" });
        if (!Guid.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId))
            return Unauthorized();

        // A delayed logout from A can never delete an installation now owned by B.
        var rows = await db.DeviceSubscriptions.Where(d => d.UserId == userId &&
            ((installationId != null && d.InstallationId == installationId) ||
             (req.PlayerId != null && d.OneSignalPlayerId == req.PlayerId)))
            .ExecuteDeleteAsync();
        return Ok(new { removed = rows });
    }

    private static bool TryInstallation(string? raw, out string? id)
    {
        id = null;
        if (string.IsNullOrWhiteSpace(raw)) return true; // legacy OneSignal clients
        if (!Guid.TryParse(raw, out var parsed) || parsed == Guid.Empty) return false;
        id = parsed.ToString();
        return true;
    }
}

public record RegisterDeviceRequest(string? PlayerId, string? Platform, string? InstallationId = null);
public record RegisterVoipRequest(string Token, string? InstallationId = null);
