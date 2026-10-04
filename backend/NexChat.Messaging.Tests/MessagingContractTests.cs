using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using NexChat.API.Controllers;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using NexChat.API.Hubs;
using NexChat.API.Services;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using NexChat.Infrastructure.Services;
using Xunit;

namespace NexChat.Messaging.Tests;

public sealed class MessagingContractTests
{
    [Fact]
    public async Task HttpSnapshotRequiresAuthenticationAndCurrentParticipantAccess()
    {
        Assert.NotEmpty(typeof(ConversationsController).GetCustomAttributes(typeof(AuthorizeAttribute), true));
        await using var f = await Fixture.Create();
        var anonymous = f.Controller(f.A.Id);
        anonymous.ControllerContext.HttpContext.User = new ClaimsPrincipal(new ClaimsIdentity());
        Assert.IsType<UnauthorizedResult>((await anonymous.GetMessages(f.Conversation.Id)).Result);
        Assert.IsType<NotFoundResult>((await f.Controller(f.C.Id).GetMessages(f.Conversation.Id)).Result);
        Assert.IsType<NotFoundResult>((await f.Controller(f.A.Id).GetMessages(Guid.NewGuid())).Result);
        Assert.IsType<OkObjectResult>((await f.Controller(f.B.Id).GetMessages(f.Conversation.Id)).Result);
        f.Db.UserConversationDeletions.Add(new() { UserId = f.B.Id, ConversationId = f.Conversation.Id });
        await f.Db.SaveChangesAsync();
        Assert.IsType<NotFoundResult>((await f.Controller(f.B.Id).GetMessages(f.Conversation.Id)).Result);

        var group = new Conversation { Type = ConversationType.Group, Name = "group" };
        f.Db.Conversations.Add(group);
        var member = new ConversationMember { ConversationId = group.Id, UserId = f.C.Id };
        f.Db.ConversationMembers.Add(member);
        await f.Db.SaveChangesAsync();
        Assert.IsType<OkObjectResult>((await f.Controller(f.C.Id).GetMessages(group.Id)).Result);
        f.Db.ConversationMembers.Remove(member);
        await f.Db.SaveChangesAsync();
        Assert.IsType<NotFoundResult>((await f.Controller(f.C.Id).GetMessages(group.Id)).Result);
    }

    [Fact]
    public async Task HttpSnapshotUsesIdenticalSocketProjectionAndProtectsPrivateMediaAndQuotes()
    {
        await using var f = await Fixture.Create();
        var other = new Conversation { User1Id = f.A.Id, User2Id = f.C.Id };
        f.Db.Conversations.Add(other);
        var hidden = new ConversationMessage { ConversationId = f.Conversation.Id, SenderId = f.A.Id, Content = "personally hidden" };
        var removed = new ConversationMessage { ConversationId = f.Conversation.Id, SenderId = f.A.Id, Content = "deleted", DeletedForEveryone = true };
        var expired = new ConversationMessage { ConversationId = f.Conversation.Id, SenderId = f.A.Id, Content = "expired", ExpiresAt = DateTime.UtcNow.AddMinutes(-1) };
        var foreign = new ConversationMessage { ConversationId = other.Id, SenderId = f.A.Id, Content = "other room secret" };
        var media = new ConversationMessage { ConversationId = f.Conversation.Id, SenderId = f.A.Id, Content = "/private/media.jpg", Type = "image", IsViewOnce = true };
        f.Db.ConversationMessages.AddRange(hidden, removed, expired, foreign, media);
        f.Db.UserMessageDeletions.Add(new() { UserId = f.B.Id, MessageId = hidden.Id });
        f.Db.ViewOnceReceipts.Add(new() { UserId = f.B.Id, MessageId = media.Id });
        foreach (var source in new[] { hidden, removed, expired, foreign, media })
            f.Db.ConversationMessages.Add(new() { ConversationId = f.Conversation.Id, SenderId = f.B.Id, Content = "reply", ReplyToMessageId = source.Id });
        await f.Db.SaveChangesAsync();
        var result = Assert.IsType<OkObjectResult>((await f.Controller(f.B.Id).GetMessages(f.Conversation.Id)).Result);
        var snapshot = Json(result.Value!);
        var messages = snapshot.GetProperty("Messages").EnumerateArray().ToList();
        Assert.Equal(f.Conversation.Id, snapshot.GetProperty("ConversationId").GetGuid());
        Assert.Equal(6, messages.Count);
        Assert.All(messages, m => Assert.Equal(f.Conversation.Id, m.GetProperty("ConversationId").GetGuid()));
        var projectedMedia = messages.Single(m => m.GetProperty("Id").GetGuid() == media.Id);
        Assert.Equal("", projectedMedia.GetProperty("Content").GetString());
        Assert.True(projectedMedia.GetProperty("ViewOnceOpened").GetBoolean());
        foreach (var source in new[] { hidden, removed, expired, foreign })
        {
            var reply = messages.Single(m => m.GetProperty("ReplyToMessageId").ValueKind != JsonValueKind.Null && m.GetProperty("ReplyToMessageId").GetGuid() == source.Id);
            Assert.True(reply.GetProperty("ReplyToUnavailable").GetBoolean());
            Assert.Equal(JsonValueKind.Null, reply.GetProperty("ReplyToContent").ValueKind);
        }
        Assert.DoesNotContain("/private/media.jpg", snapshot.GetRawText());
        Assert.Empty(await f.Db.UserConversationStates.ToListAsync());
        await f.ConversationHub(f.B.Id).JoinConversation(f.Conversation.Id.ToString());
        var socket = Json(f.Clients.Events.Last(e => e.Method == "ConversationJoined").Arguments[0]!);
        Assert.Equal(snapshot.GetProperty("Messages").GetRawText(), socket.GetProperty("Messages").GetRawText());
        Assert.Equal(snapshot.GetProperty("HasMore").GetBoolean(), socket.GetProperty("HasMore").GetBoolean());
    }

    [Fact]
    public async Task HttpSnapshotReturnsOnlyTheLatestSixtyMessagesInChronologicalOrder()
    {
        await using var f = await Fixture.Create();
        var at = DateTime.UtcNow.AddHours(-1);
        for (var i = 0; i < 65; i++)
            f.Db.ConversationMessages.Add(new() { ConversationId = f.Conversation.Id, SenderId = f.A.Id, Content = i.ToString(), SentAt = at.AddSeconds(i) });
        await f.Db.SaveChangesAsync();
        var result = Assert.IsType<OkObjectResult>((await f.Controller(f.B.Id).GetMessages(f.Conversation.Id)).Result);
        var snapshot = Json(result.Value!);
        Assert.True(snapshot.GetProperty("HasMore").GetBoolean());
        Assert.Equal(Enumerable.Range(5, 60).Select(i => i.ToString()), snapshot.GetProperty("Messages").EnumerateArray().Select(m => m.GetProperty("Content").GetString()));
    }

    [Fact]
    public async Task ConversationRetryReturnsTheSameDurableIdWithoutDuplicateEcho()
    {
        await using var f = await Fixture.Create();
        var hub = f.ConversationHub(f.A.Id);
        var first = Json(await hub.SendMessageWithClientId(f.Conversation.Id.ToString(), "one", "text", null, false, "stable-1"));
        var retry = Json(await hub.SendMessageWithClientId(f.Conversation.Id.ToString(), "one", "text", null, false, "stable-1"));
        Assert.Equal(first.GetProperty("Id").GetGuid(), retry.GetProperty("Id").GetGuid());
        Assert.Equal(f.Conversation.Id, first.GetProperty("ConversationId").GetGuid());
        Assert.Equal("stable-1", first.GetProperty("ClientMessageId").GetString());
        Assert.Single(await f.Db.ConversationMessages.ToListAsync());
        Assert.Single(f.Clients.Events, e => e.Method == "ReceiveMessage" && e.Target == "user:" + f.A.Id);
        Assert.DoesNotContain(f.Clients.Events, e => e.Method == "ReceiveMessage" && e.Target == "caller");
    }

    [Theory]
    [InlineData("short_film", "{\"id\":\"00000000-0000-0000-0000-000000000123\",\"title\":\"Shared reel\",\"thumbnailUrl\":null}")]
    [InlineData("story_share", "{\"userId\":\"00000000-0000-0000-0000-000000000123\",\"slideId\":\"00000000-0000-0000-0000-000000000456\",\"name\":\"Shared story\",\"mediaType\":\"text\",\"caption\":\"Hello\"}")]
    public async Task ReelAndStorySharesReturnAcceptedScopedPayloadAndDeduplicate(string type, string content)
    {
        await using var f = await Fixture.Create();
        var hub = f.ConversationHub(f.A.Id);
        var first = Json(await hub.SendMessageWithClientId(f.Conversation.Id.ToString(), content, type, null, false, "share-1"));
        var retry = Json(await hub.SendMessageWithClientId(f.Conversation.Id.ToString(), content, type, null, false, "share-1"));
        Assert.Equal(first.GetProperty("Id").GetGuid(), retry.GetProperty("Id").GetGuid());
        Assert.Equal(f.Conversation.Id, first.GetProperty("ConversationId").GetGuid());
        Assert.Equal(type, first.GetProperty("Type").GetString());
        Assert.Equal(content, first.GetProperty("Content").GetString());
        Assert.Equal("share-1", first.GetProperty("ClientMessageId").GetString());
        Assert.Single(await f.Db.ConversationMessages.ToListAsync());
        Assert.Single(f.Clients.Events, e => e.Method == "ReceiveMessage" && e.Target == "user:" + f.B.Id);
        var error = await Assert.ThrowsAsync<HubException>(() => hub.SendMessageWithClientId(f.Conversation.Id.ToString(), " ", type, null, false, "share-invalid"));
        Assert.Equal("Message must contain between 1 and 5000 characters", error.Message);
    }

    [Fact]
    public async Task DatabaseUniqueConstraintRejectsDuplicateRetryRowsButScopesKeys()
    {
        await using var f = await Fixture.Create();
        f.Db.ConversationMessages.Add(new() { ConversationId = f.Conversation.Id, SenderId = f.A.Id, ClientMessageId = "same", Content = "one" });
        await f.Db.SaveChangesAsync();
        f.Db.ConversationMessages.Add(new() { ConversationId = f.Conversation.Id, SenderId = f.A.Id, ClientMessageId = "same", Content = "two" });
        await Assert.ThrowsAsync<DbUpdateException>(() => f.Db.SaveChangesAsync());
        f.Db.ChangeTracker.Clear();
        f.Db.ConversationMessages.Add(new() { ConversationId = f.Conversation.Id, SenderId = f.B.Id, ClientMessageId = "same", Content = "other sender" });
        await f.Db.SaveChangesAsync();
        Assert.Equal(2, await f.Db.ConversationMessages.CountAsync());
    }

    [Fact]
    public async Task BlockIsBilateralAndRejectedSendsDoNotPersist()
    {
        await using var f = await Fixture.Create();
        f.Db.UserBlocks.Add(new() { BlockerId = f.B.Id, BlockedUserId = f.A.Id });
        await f.Db.SaveChangesAsync();
        await Assert.ThrowsAsync<HubException>(() => f.ConversationHub(f.A.Id).SendMessageWithClientId(f.Conversation.Id.ToString(), "blocked", "text", null, false, "blocked"));
        await Assert.ThrowsAsync<HubException>(() => f.ConversationHub(f.B.Id).SendMessageWithClientId(f.Conversation.Id.ToString(), "blocked", "text", null, false, "blocked"));
        await Assert.ThrowsAsync<HubException>(() => f.ConversationHub(f.A.Id).SendMessage(f.Conversation.Id.ToString(), " "));
        Assert.Empty(await f.Db.ConversationMessages.ToListAsync());
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void PomeloTranslatesTheActualStrictHistoryCursorWithoutConnecting(bool mariaDb)
    {
        ServerVersion version = mariaDb ? new MariaDbServerVersion(new Version(10, 11, 0)) : new MySqlServerVersion(new Version(8, 0, 21));
        using var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
            .UseMySql("Server=127.0.0.1;Database=query_translation_only;User=unused", version).Options);
        var sql = ConversationMessageQueries.VisiblePage(db, Guid.NewGuid(), Guid.NewGuid(), DateTime.UtcNow, Guid.NewGuid()).Take(61).ToQueryString();
        Assert.Contains("`SentAt` < @p0", sql);
        Assert.Contains("`SentAt` = @p1 AND `Id` < @p2", sql);
        Assert.Contains("`Id` DESC", sql);
        Assert.Contains("NOT EXISTS", sql);
        Assert.Contains("LIMIT", sql);
        Assert.DoesNotContain("`Id` <> @p2", sql);
    }

    [Fact]
    public async Task EqualTimestampHistoryPagesAreStrictlyOlderAndReachEveryRow()
    {
        await using var f = await Fixture.Create();
        var at = DateTime.UtcNow.AddHours(-1);
        for (var i = 1; i <= 125; i++) f.Db.ConversationMessages.Add(new()
        {
            Id = Guid.Parse($"00000000-0000-0000-0000-{i:x12}"), ConversationId = f.Conversation.Id,
            SenderId = f.A.Id, Content = $"message {i}", SentAt = at
        });
        await f.Db.SaveChangesAsync();
        var hub = f.ConversationHub(f.B.Id);
        await hub.JoinConversation(f.Conversation.Id.ToString());
        var joined = Json(f.Clients.Events.Last(e => e.Method == "ConversationJoined").Arguments[0]!);
        var ids = joined.GetProperty("Messages").EnumerateArray().Select(x => x.GetProperty("Id").GetGuid()).ToList();
        var hasMore = joined.GetProperty("HasMore").GetBoolean();
        while (hasMore)
        {
            await hub.GetOlderMessages(f.Conversation.Id.ToString(), ids[0].ToString(), 60);
            var page = Json(f.Clients.Events.Last(e => e.Method == "OlderMessages").Arguments[0]!);
            var older = page.GetProperty("Messages").EnumerateArray().Select(x => x.GetProperty("Id").GetGuid()).ToList();
            Assert.NotEmpty(older);
            Assert.Empty(older.Intersect(ids));
            ids.InsertRange(0, older);
            hasMore = page.GetProperty("HasMore").GetBoolean();
        }
        Assert.Equal(125, ids.Count);
        Assert.Equal(125, ids.Distinct().Count());
    }

    [Fact]
    public async Task DeletedAndExpiredQuotedMessagesAreUnavailableAndDeletionReachesUserDevices()
    {
        await using var f = await Fixture.Create();
        var original = new ConversationMessage { ConversationId = f.Conversation.Id, SenderId = f.A.Id, Content = "secret", SentAt = DateTime.UtcNow.AddHours(-1) };
        var expired = new ConversationMessage { ConversationId = f.Conversation.Id, SenderId = f.A.Id, Content = "expired secret", ExpiresAt = DateTime.UtcNow.AddMinutes(-1) };
        f.Db.ConversationMessages.AddRange(original, expired);
        f.Db.ConversationMessages.AddRange(
            new() { ConversationId = f.Conversation.Id, SenderId = f.B.Id, Content = "reply", ReplyToMessageId = original.Id },
            new() { ConversationId = f.Conversation.Id, SenderId = f.B.Id, Content = "reply expired", ReplyToMessageId = expired.Id });
        await f.Db.SaveChangesAsync();
        await f.ConversationHub(f.A.Id).DeleteMessageForEveryone(f.Conversation.Id.ToString(), original.Id.ToString());
        var deletes = f.Clients.Events.Where(e => e.Method == "MessageDeletedForEveryoneV2").ToList();
        Assert.Contains(deletes, e => e.Target == "user:" + f.B.Id);
        AssertLegacy(f.Clients, "MessageDeletedForEveryone", "group:" + f.Conversation.Id, original.Id);
        Assert.All(deletes, e => Assert.Equal(f.Conversation.Id, Json(e.Arguments[0]!).GetProperty("ConversationId").GetGuid()));
        await f.ConversationHub(f.B.Id).JoinConversation(f.Conversation.Id.ToString());
        var messages = Json(f.Clients.Events.Last(e => e.Method == "ConversationJoined").Arguments[0]!).GetProperty("Messages").EnumerateArray().ToList();
        Assert.Equal(2, messages.Count);
        Assert.All(messages, m => { Assert.True(m.GetProperty("ReplyToUnavailable").GetBoolean()); Assert.Equal(JsonValueKind.Null, m.GetProperty("ReplyToContent").ValueKind); });
    }

    [Fact]
    public async Task PersonalDeletionIsBoundToConversationAndBroadcastToOwnDevices()
    {
        await using var f = await Fixture.Create();
        var other = new Conversation { User1Id = f.A.Id, User2Id = f.C.Id };
        var message = new ConversationMessage { ConversationId = other.Id, SenderId = f.A.Id, Content = "other room" };
        f.Db.Conversations.Add(other); f.Db.ConversationMessages.Add(message); await f.Db.SaveChangesAsync();
        var hub = f.ConversationHub(f.A.Id);
        await Assert.ThrowsAsync<HubException>(() => hub.DeleteMessageForMe(f.Conversation.Id.ToString(), message.Id.ToString()));
        Assert.Empty(await f.Db.UserMessageDeletions.ToListAsync());
        await hub.DeleteMessageForMe(other.Id.ToString(), message.Id.ToString());
        Assert.Contains(f.Clients.Events, e => e.Method == "MessageDeletedForMeV2" && e.Target == "user:" + f.A.Id);
        AssertLegacy(f.Clients, "MessageDeletedForMe", "caller", message.Id);
    }

    [Fact]
    public async Task GroupInboxFanoutIncludesAuthoritativeUnreadForMembersOutsideRoom()
    {
        await using var f = await Fixture.Create();
        var group = new Conversation { Type = ConversationType.Group, Name = "group" };
        f.Db.Conversations.Add(group);
        foreach (var user in new[] { f.A, f.B, f.C }) f.Db.ConversationMembers.Add(new() { ConversationId = group.Id, UserId = user.Id });
        await f.Db.SaveChangesAsync();
        await f.ConversationHub(f.A.Id).SendMessageWithClientId(group.Id.ToString(), "hello group", "text", null, false, "group-1");
        foreach (var user in new[] { f.A, f.B, f.C })
        {
            var update = f.Clients.Events.Single(e => e.Method == "ConversationListUpdated" && e.Target == "user:" + user.Id);
            Assert.Equal(user == f.A ? 0 : 1, Json(update.Arguments[0]!).GetProperty("UnreadCount").GetInt32());
        }
        Assert.Equal(2, await f.Db.NotificationOutboxItems.CountAsync());
        Assert.All(await f.Db.NotificationOutboxItems.ToListAsync(), item => Assert.NotEqual(f.A.Id, item.RecipientUserId));
        f.Db.ConversationMembers.Remove(await f.Db.ConversationMembers.SingleAsync(m => m.ConversationId == group.Id && m.UserId == f.C.Id));
        await f.Db.SaveChangesAsync();
        await Assert.ThrowsAsync<HubException>(() => f.ConversationHub(f.C.Id).SendMessageWithClientId(group.Id.ToString(), "removed", "text", null, false, "group-2"));
    }

    [Fact]
    public async Task ChatSessionRetryIsDurableAndDisconnectDoesNotEndSession()
    {
        await using var f = await Fixture.Create();
        var session = new ChatSession { User1Id = f.A.Id, User2Id = f.B.Id, Type = "code" };
        f.Db.ChatSessions.Add(session); await f.Db.SaveChangesAsync();
        var hub = f.ChatHub(f.A.Id);
        var first = Json(await hub.SendMessageWithClientId(session.Id.ToString(), "hello", "text", "session-1"));
        var retry = Json(await hub.SendMessageWithClientId(session.Id.ToString(), "hello", "text", "session-1"));
        Assert.Equal(first.GetProperty("Id").GetGuid(), retry.GetProperty("Id").GetGuid());
        Assert.Equal(session.Id, first.GetProperty("SessionId").GetGuid());
        Assert.Single(await f.Db.Messages.ToListAsync());
        await hub.OnDisconnectedAsync(new IOException("transport lost"));
        Assert.Null((await f.Db.ChatSessions.FindAsync(session.Id))!.EndedAt);
        await hub.LeaveSession(session.Id.ToString());
        Assert.NotNull((await f.Db.ChatSessions.FindAsync(session.Id))!.EndedAt);
        Assert.All(f.Clients.Events.Where(e => e.Method == "SessionEndedV2"), e => Assert.Equal(session.Id, Json(e.Arguments[0]!).GetProperty("SessionId").GetGuid()));
        AssertLegacy(f.Clients, "SessionEnded", "group:" + session.Id, f.A.Id);
        Assert.Equal(2, f.Clients.Events.Count(e => e.Method == "SessionEndedV2"));
    }

    [Fact]
    public async Task LostLiveAcknowledgmentRetryReturnsOriginalAndDoesNotResend()
    {
        await using var f = await Fixture.Create();
        f.Clients.FailDelivery = true;
        var accepted = Json(await f.ConversationHub(f.A.Id).SendMessageWithClientId(f.Conversation.Id.ToString(), "committed", "text", null, false, "lost-ack"));
        f.Clients.FailDelivery = false;
        var retried = Json(await f.ConversationHub(f.A.Id).SendMessageWithClientId(f.Conversation.Id.ToString(), "committed", "text", null, false, "lost-ack"));
        Assert.Equal(accepted.GetProperty("Id").GetGuid(), retried.GetProperty("Id").GetGuid());
        Assert.Equal(1, await f.Db.ConversationMessages.CountAsync());
        Assert.Empty(f.Clients.Events);
    }

    [Fact]
    public async Task ReadWatermarksNeverRegressAndEventsContainTheirConversation()
    {
        await using var f = await Fixture.Create();
        var newer = DateTime.UtcNow.AddMinutes(1);
        await ConversationDelivery.MarkReadAsync(f.Db, f.Conversation.Id, f.A.Id, newer);
        await ConversationDelivery.MarkReadAsync(f.Db, f.Conversation.Id, f.A.Id, newer.AddMinutes(-10));
        Assert.Equal(newer, (await f.Db.UserConversationStates.SingleAsync()).LastReadAt);
        await f.ConversationHub(f.A.Id).MarkAsRead(f.Conversation.Id.ToString());
        Assert.All(f.Clients.Events.Where(e => e.Method is "PartnerReadUpTo" or "ConversationRead"),
            e => Assert.Equal(f.Conversation.Id, Json(e.Arguments[0]!).GetProperty("ConversationId").GetGuid()));
        Assert.Equal(newer, (await f.Db.UserConversationStates.AsNoTracking().SingleAsync()).LastReadAt);
    }

    [Fact]
    public async Task RemovedMemberIsEjectedFromEveryKnownConnection()
    {
        await using var f = await Fixture.Create();
        var group = Guid.NewGuid();
        ConversationDelivery.Joined(group, f.A.Id, "first-device");
        ConversationDelivery.Joined(group, f.A.Id, "second-device");
        await ConversationDelivery.EjectAsync(f.Groups, f.Clients, group, f.A.Id);
        Assert.Equal(2, f.Groups.Removed.Count);
        Assert.All(f.Groups.Removed, e => Assert.Equal(group.ToString(), e.Group));
        var ev = Assert.Single(f.Clients.Events, e => e.Method == "ConversationRemoved");
        Assert.Equal("user:" + f.A.Id, ev.Target);
        Assert.Equal(group, Json(ev.Arguments[0]!).GetProperty("ConversationId").GetGuid());
    }

    [Fact]
    public async Task TypingRequiresMembershipAndIncludesScope()
    {
        await using var f = await Fixture.Create();
        await f.ConversationHub(f.C.Id).StartTyping(f.Conversation.Id.ToString());
        Assert.Empty(f.Clients.Events);
        await f.ConversationHub(f.A.Id).StartTyping(f.Conversation.Id.ToString());
        var payload = Json(Assert.Single(f.Clients.Events, e => e.Method == "UserTypingV2").Arguments[0]!);
        Assert.Equal(f.Conversation.Id, payload.GetProperty("ConversationId").GetGuid());
        Assert.Equal(f.A.Id, payload.GetProperty("UserId").GetGuid());
        AssertLegacy(f.Clients, "UserTyping", "othersInGroup:" + f.Conversation.Id, f.A.Id);
        await f.ConversationHub(f.A.Id).StopTyping(f.Conversation.Id.ToString());
        AssertLegacy(f.Clients, "UserStoppedTyping", "othersInGroup:" + f.Conversation.Id, f.A.Id);
        var stopped = Json(Assert.Single(f.Clients.Events, e => e.Method == "UserStoppedTypingV2").Arguments[0]!);
        Assert.Equal(f.Conversation.Id, stopped.GetProperty("ConversationId").GetGuid());
    }

    [Fact]
    public async Task ConversationDeletionPreservesScalarCallerAndAddsScopedAccountEvent()
    {
        await using var f = await Fixture.Create();
        await f.ConversationHub(f.A.Id).DeleteConversationForMe(f.Conversation.Id.ToString());
        AssertLegacy(f.Clients, "ConversationDeletedForMe", "caller", f.Conversation.Id);
        var modern = Assert.Single(f.Clients.Events, e => e.Method == "ConversationDeletedForMeV2");
        Assert.Equal("user:" + f.A.Id, modern.Target);
        Assert.Equal(f.Conversation.Id, Json(modern.Arguments[0]!).GetProperty("ConversationId").GetGuid());
    }

    [Fact]
    public async Task SessionTypingPreservesScalarRoomAndAddsScopedAccountEvents()
    {
        await using var f = await Fixture.Create();
        var session = new ChatSession { User1Id = f.A.Id, User2Id = f.B.Id, Type = "code" };
        f.Db.ChatSessions.Add(session); await f.Db.SaveChangesAsync();
        await f.ChatHub(f.C.Id).StartTyping(session.Id.ToString());
        Assert.Empty(f.Clients.Events);
        await f.ChatHub(f.A.Id).StartTyping(session.Id.ToString());
        await f.ChatHub(f.A.Id).StopTyping(session.Id.ToString());
        foreach (var name in new[] { "UserTyping", "UserStoppedTyping" })
        {
            AssertLegacy(f.Clients, name, "othersInGroup:" + session.Id, f.A.Id);
            var modern = Assert.Single(f.Clients.Events, e => e.Method == name + "V2");
            Assert.Equal("user:" + f.B.Id, modern.Target);
            var payload = Json(modern.Arguments[0]!);
            Assert.Equal(session.Id, payload.GetProperty("SessionId").GetGuid());
            Assert.Equal(f.A.Id, payload.GetProperty("UserId").GetGuid());
        }
    }

    [Fact]
    public async Task InactivityCleanupPreservesOneHourPolicyAndEmitsBothSessionEndContracts()
    {
        await using var f = await Fixture.Create();
        var stale = new ChatSession { User1Id = f.A.Id, User2Id = f.B.Id, Type = "code", StartedAt = DateTime.UtcNow.AddHours(-2) };
        var recent = new ChatSession { User1Id = f.A.Id, User2Id = f.C.Id, Type = "code", StartedAt = DateTime.UtcNow.AddMinutes(-30) };
        f.Db.ChatSessions.AddRange(stale, recent); await f.Db.SaveChangesAsync();
        await using var services = new ServiceCollection()
            .AddScoped(_ => new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseSqlite(f.Connection).Options))
            .AddSingleton<IHubContext<ChatHub>>(new RecordingChatHubContext(f.Clients, f.Groups))
            .BuildServiceProvider();
        using var cleanup = new InactiveSessionCleanupService(services.GetRequiredService<IServiceScopeFactory>());
        var pass = typeof(InactiveSessionCleanupService).GetMethod("CloseInactiveSessionsAsync", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!;
        await (Task)pass.Invoke(cleanup, null)!;
        Assert.NotNull((await f.Db.ChatSessions.AsNoTracking().SingleAsync(s => s.Id == stale.Id)).EndedAt);
        Assert.Null((await f.Db.ChatSessions.AsNoTracking().SingleAsync(s => s.Id == recent.Id)).EndedAt);
        AssertLegacy(f.Clients, "SessionEnded", "group:" + stale.Id, Guid.Empty);
        var modern = f.Clients.Events.Where(e => e.Method == "SessionEndedV2").ToList();
        Assert.Equal(2, modern.Count);
        Assert.All(modern, e => Assert.Equal(stale.Id, Json(e.Arguments[0]!).GetProperty("SessionId").GetGuid()));
    }

    [Fact]
    public async Task MessagingMigrationIsDiscovered()
    {
        await using var f = await Fixture.Create();
        Assert.Contains("20261004172200_AddMessageClientIds", f.Db.Database.GetMigrations());
    }

    [Fact]
    public void SignalRLegacyAndIdempotentAritiesRemainUnambiguous()
    {
        Assert.Equal(5, typeof(ConversationHub).GetMethod("SendMessage")!.GetParameters().Length);
        Assert.Equal(6, typeof(ConversationHub).GetMethod("SendMessageWithClientId")!.GetParameters().Length);
        Assert.Equal(3, typeof(ChatHub).GetMethod("SendMessage")!.GetParameters().Length);
        Assert.Equal(4, typeof(ChatHub).GetMethod("SendMessageWithClientId")!.GetParameters().Length);
    }

    static JsonElement Json(object value) => JsonSerializer.SerializeToElement(value);
    static void AssertLegacy(RecordingClients clients, string method, string target, Guid value)
    {
        var ev = Assert.Single(clients.Events, e => e.Method == method);
        Assert.Equal(target, ev.Target);
        Assert.Equal(value, Assert.IsType<Guid>(Assert.Single(ev.Arguments)));
    }

    sealed class Fixture : IAsyncDisposable
    {
        public required SqliteConnection Connection;
        public required AppDbContext Db;
        public RecordingClients Clients { get; } = new();
        public RecordingGroups Groups { get; } = new();
        public User A { get; } = new() { Name = "A", UniqueCode = "A" };
        public User B { get; } = new() { Name = "B", UniqueCode = "B" };
        public User C { get; } = new() { Name = "C", UniqueCode = "C" };
        public Conversation Conversation { get; } = new();
        public static async Task<Fixture> Create()
        {
            var connection = new SqliteConnection("DataSource=:memory:"); await connection.OpenAsync();
            connection.CreateCollation("utf8mb4_bin", string.CompareOrdinal);
            var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseSqlite(connection).Options);
            await db.Database.EnsureCreatedAsync();
            var fixture = new Fixture { Connection = connection, Db = db };
            db.Users.AddRange(fixture.A, fixture.B, fixture.C);
            fixture.Conversation.User1Id = fixture.A.Id; fixture.Conversation.User2Id = fixture.B.Id;
            db.Conversations.Add(fixture.Conversation); await db.SaveChangesAsync();
            return fixture;
        }
        ServiceProvider? services;
        NotificationOutboxService Outbox()
        {
            services ??= new ServiceCollection()
                .AddScoped(_ => new AppDbContext(new DbContextOptionsBuilder<AppDbContext>().UseSqlite(Connection).Options))
                .AddScoped(sp => new OneSignalService(new HttpClient(new RejectNetworkHandler()), Options.Create(new OneSignalOptions()), sp.GetRequiredService<AppDbContext>(), sp.GetRequiredService<IServiceScopeFactory>(), NullLogger<OneSignalService>.Instance))
                .BuildServiceProvider();
            return new(services.GetRequiredService<IServiceScopeFactory>(), Options.Create(new NotificationFeaturesOptions()), NullLogger<NotificationOutboxService>.Instance);
        }
        public ConversationHub ConversationHub(Guid userId)
        {
            var crypto = new PassthroughCrypto();
            var environment = new TestEnvironment();
            var storage = new MediaStorageService(environment, new ConfigurationBuilder().Build());
            return new ConversationHub(Db, Outbox(), null!, NullLogger<ConversationHub>.Instance, null!, crypto, new NoProfanity(),
                new OfficialAnnouncementConversationService(Db, crypto, NullLogger<OfficialAnnouncementConversationService>.Instance),
                new SupportConversationService(Db, crypto, NullLogger<SupportConversationService>.Instance),
                storage, new ViewOnceMediaService(Db, storage, crypto, TimeProvider.System))
                { Context = new TestContext(userId), Clients = Clients, Groups = Groups };
        }
        public ConversationsController Controller(Guid userId)
        {
            var crypto = new PassthroughCrypto();
            return new ConversationsController(Db, Outbox(), crypto, null!,
                new SupportConversationService(Db, crypto, NullLogger<SupportConversationService>.Instance),
                new OfficialAnnouncementConversationService(Db, crypto, NullLogger<OfficialAnnouncementConversationService>.Instance))
            {
                ControllerContext = new ControllerContext
                {
                    HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, userId.ToString()) }, "test")) }
                }
            };
        }
        public ChatHub ChatHub(Guid userId) => new(Db, Outbox(), new NoProfanity()) { Context = new TestContext(userId), Clients = Clients, Groups = Groups };
        public async ValueTask DisposeAsync() { if (services != null) await services.DisposeAsync(); await Db.DisposeAsync(); await Connection.DisposeAsync(); }
    }
    sealed class TestEnvironment : IWebHostEnvironment
    {
        public string ApplicationName { get; set; } = "NexChat.Messaging.Tests";
        public string EnvironmentName { get; set; } = "Test";
        public string ContentRootPath { get; set; } = Path.GetTempPath();
        public string WebRootPath { get; set; } = Path.Combine(Path.GetTempPath(), "nexchat-test-wwwroot");
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
        public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
    }
    sealed class RejectNetworkHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("Regression tests must never contact a notification provider");
    }
    sealed class PassthroughCrypto : IConversationMessageCrypto { public string EncryptForStorage(string value) => value; public string DecryptFromStorage(string value) => value; }
    sealed class NoProfanity : IProfanityMasker { public string Mask(string value) => value; }
    sealed class TestContext(Guid userId) : HubCallerContext
    {
        public override string ConnectionId { get; } = Guid.NewGuid().ToString();
        public override string? UserIdentifier => userId.ToString();
        public override ClaimsPrincipal? User { get; } = new(new ClaimsIdentity(new[] { new Claim(ClaimTypes.NameIdentifier, userId.ToString()) }, "test"));
        public override IDictionary<object, object?> Items { get; } = new Dictionary<object, object?>();
        public override IFeatureCollection Features { get; } = new FeatureCollection();
        public override CancellationToken ConnectionAborted => CancellationToken.None;
        public override void Abort() { }
    }
    sealed class RecordingGroups : IGroupManager
    {
        public List<(string Connection, string Group)> Removed { get; } = [];
        public Task AddToGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task RemoveFromGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) { Removed.Add((connectionId, groupName)); return Task.CompletedTask; }
    }
    sealed record Event(string Target, string Method, object?[] Arguments);
    sealed class RecordingClients : IHubCallerClients, IHubClients
    {
        public List<Event> Events { get; } = [];
        public bool FailDelivery { get; set; }
        IClientProxy Proxy(string target) => new RecordingProxy(target, Events, () => FailDelivery);
        public IClientProxy All => Proxy("all"); public IClientProxy Caller => Proxy("caller"); public IClientProxy Others => Proxy("others");
        public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => Proxy("allExcept");
        public IClientProxy Client(string connectionId) => Proxy("client:" + connectionId);
        public IClientProxy Clients(IReadOnlyList<string> connectionIds) => Proxy("clients");
        public IClientProxy Group(string groupName) => Proxy("group:" + groupName);
        public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => Proxy("groupExcept:" + groupName);
        public IClientProxy Groups(IReadOnlyList<string> groupNames) => Proxy("groups");
        public IClientProxy OthersInGroup(string groupName) => Proxy("othersInGroup:" + groupName);
        public IClientProxy User(string userId) => Proxy("user:" + userId);
        public IClientProxy Users(IReadOnlyList<string> userIds) => Proxy("users:" + string.Join(",", userIds));
    }
    sealed class RecordingChatHubContext(RecordingClients clients, RecordingGroups groups) : IHubContext<ChatHub>
    {
        public IHubClients Clients => clients;
        public IGroupManager Groups => groups;
    }
    sealed class RecordingProxy(string target, List<Event> events, Func<bool> fail) : IClientProxy
    {
        public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default) { if (fail()) throw new IOException("socket closed after commit"); events.Add(new(target, method, args)); return Task.CompletedTask; }
    }
}
