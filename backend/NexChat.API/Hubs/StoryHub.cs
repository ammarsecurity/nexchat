using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using System.Security.Claims;

namespace NexChat.API.Hubs;

[Authorize]
public class StoryHub : Hub
{
    public override Task OnConnectedAsync()
    {
        var userId = Context.User?.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!string.IsNullOrEmpty(userId))
            return Groups.AddToGroupAsync(Context.ConnectionId, $"user_{userId}");
        return base.OnConnectedAsync();
    }
}
