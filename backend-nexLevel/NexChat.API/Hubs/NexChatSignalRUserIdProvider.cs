using System.Security.Claims;
using Microsoft.AspNetCore.SignalR;

namespace NexChat.API.Hubs;

/// <summary>
/// يضمن أن <see cref="IClientProxy"/> / Clients.User يطابق معرف المستخدم في JWT (NameIdentifier أو sub).
/// </summary>
public sealed class NexChatSignalRUserIdProvider : IUserIdProvider
{
    public string? GetUserId(HubConnectionContext connection)
    {
        var user = connection.User;
        if (user?.Identity?.IsAuthenticated != true)
            return null;

        var id = user.FindFirstValue(ClaimTypes.NameIdentifier)
                 ?? user.FindFirstValue("sub");

        return string.IsNullOrEmpty(id) ? null : id;
    }
}
