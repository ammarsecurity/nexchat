using System.Text.Json;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using NexChat.API.Hubs;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;

namespace NexChat.API.Services;

/// <summary>Awaited expiration work shared by both hubs; no fire-and-forget use of a disposed hub/DbContext.</summary>
public static class CallLifecycleMaintenance
{
    public static async Task PurgeAsync(AppDbContext db, NotificationOutboxService outbox, IServiceProvider services)
    {
        var expired = new List<(Guid Room, CallPresenceStore.PendingCall Call)>();
        CallPresenceStore.PurgeStale((room, p) => expired.Add((room, p)));
        foreach (var (room, p) in expired)
        {
            var secs = CallPresenceStore.Duration(p);
            var plain = JsonSerializer.Serialize(new { status = p.Accepted ? "ended" : "missed", voiceOnly = p.VoiceOnly, durationSec = secs });
            var conversation = await db.Conversations.AnyAsync(c => c.Id == room);
            if (conversation)
            {
                var hub = services.GetRequiredService<IHubContext<ConversationHub>>();
                if (!await db.ConversationMessages.AnyAsync(m => m.Id == p.CallId))
                {
                    var msg = new ConversationMessage { Id = p.CallId, ConversationId = room, SenderId = p.CallerId,
                        Content = services.GetRequiredService<IConversationMessageCrypto>().EncryptForStorage(plain), Type = "call" };
                    db.ConversationMessages.Add(msg); await db.SaveChangesAsync();
                    foreach (var user in new[] { p.CallerId, p.RecipientId })
                    {
                        await hub.Clients.User(user.ToString()).SendAsync("ReceiveMessage", new { msg.Id, msg.ConversationId, msg.SenderId,
                            Content = plain, msg.Type, msg.SentAt, ClientMessageId = (string?)null });
                        await hub.Clients.User(user.ToString()).SendAsync("ConversationListUpdated", new { ConversationId = room,
                            LastMessagePreview = ConversationPreviewHelper.BuildCallPreview(plain), LastMessageType = "call", LastMessageAt = msg.SentAt, SenderId = p.CallerId });
                    }
                }
                foreach (var user in new[] { p.CallerId, p.RecipientId })
                    await hub.Clients.User(user.ToString()).SendAsync("VideoCallEnded", room.ToString(), secs, p.CallId.ToString());
            }
            else if (await db.ChatSessions.AnyAsync(s => s.Id == room))
            {
                var hub = services.GetRequiredService<IHubContext<ChatHub>>();
                if (!await db.Messages.AnyAsync(m => m.Id == p.CallId))
                {
                    var msg = new Message { Id = p.CallId, SessionId = room, SenderId = p.CallerId, Type = "call", Content = plain };
                    db.Messages.Add(msg); await db.SaveChangesAsync();
                    await hub.Clients.Group(room.ToString()).SendAsync("ReceiveMessage", new { msg.Id, msg.SessionId, msg.SenderId,
                        msg.Content, msg.Type, msg.SentAt, ClientMessageId = (string?)null });
                }
                foreach (var user in new[] { p.CallerId, p.RecipientId })
                    await hub.Clients.User(user.ToString()).SendAsync("VideoCallEnded", secs, room.ToString(), p.CallId.ToString());
            }
            await outbox.CancelCallPushAsync(p.CallerId, room, p.CallId);
            await outbox.CancelCallPushAsync(p.RecipientId, room, p.CallId);
        }
    }
}
