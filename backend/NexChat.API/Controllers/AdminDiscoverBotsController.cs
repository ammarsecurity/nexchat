using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using NexChat.API.Services;
using NexChat.Core.DTOs;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Controllers;

[ApiController]
[Route("api/admin/discover-bots")]
[Authorize(Policy = "AdminOnly")]
public class AdminDiscoverBotsController(
    DiscoverBotsSettingsService settings,
    DiscoverBotSeedService seed) : ControllerBase
{
    [HttpGet("config")]
    public async Task<ActionResult<DiscoverBotsStatusDto>> GetConfig(CancellationToken ct)
        => Ok(await seed.GetStatusAsync(ct));

    [HttpPut("config")]
    public async Task<IActionResult> PutConfig([FromBody] DiscoverBotsConfigDto dto, CancellationToken ct)
    {
        await settings.SaveConfigAsync(dto, ct);
        return Ok(await seed.GetStatusAsync(ct));
    }

    [HttpPost("sync")]
    public async Task<ActionResult<DiscoverBotsSyncResultDto>> Sync(CancellationToken ct)
        => Ok(await seed.SyncAsync(ct));

    [HttpPost("refresh-photos")]
    public async Task<ActionResult<object>> RefreshPhotos(CancellationToken ct)
        => Ok(await seed.RefreshPhotosAsync(ct));

    [HttpDelete]
    public async Task<ActionResult<object>> DeleteAll(CancellationToken ct)
    {
        var deleted = await seed.DeleteAllBotsAsync(ct);
        return Ok(new { deleted, status = await seed.GetStatusAsync(ct) });
    }
}
