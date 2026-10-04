using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using NexChat.Core.Entities;
using NexChat.Infrastructure.Data;
using Xunit;

namespace NexChat.Media.Tests;

// Receipt uniqueness is the concurrency boundary. These tests execute actual
// relational constraints/transactions instead of mocking AnyAsync results.
public sealed class ViewOnceReceiptRaceTests
{
    [Fact]
    public async Task UniqueReceiptRollsBackAnUnreturnedSessionInTheSameSave()
    {
        await using var connection = new Microsoft.Data.Sqlite.SqliteConnection("DataSource=:memory:");
        await connection.OpenAsync();
        connection.CreateCollation("utf8mb4_bin", string.CompareOrdinal);
        var options = new DbContextOptionsBuilder<AppDbContext>().UseSqlite(connection).Options;
        await using var db = new AppDbContext(options);
        await db.Database.EnsureCreatedAsync();
        var sender = new User { Name = "sender", UniqueCode = "sender" };
        var recipient = new User { Name = "recipient", UniqueCode = "recipient" };
        var conversation = new Conversation { User1Id = sender.Id, User2Id = recipient.Id };
        var message = new ConversationMessage { ConversationId = conversation.Id, SenderId = sender.Id, IsViewOnce = true };
        db.AddRange(sender, recipient, conversation, message);
        db.ViewOnceReceipts.Add(new ViewOnceReceipt { MessageId = message.Id, UserId = recipient.Id });
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();
        db.ViewOnceMediaSessions.Add(new ViewOnceMediaSession { MessageId = message.Id, UserId = recipient.Id, ExpiresAt = DateTime.UtcNow.AddMinutes(15) });
        db.ViewOnceReceipts.Add(new ViewOnceReceipt { MessageId = message.Id, UserId = recipient.Id });
        await Assert.ThrowsAsync<DbUpdateException>(() => db.SaveChangesAsync());
        db.ChangeTracker.Clear();
        Assert.Equal(1, await db.ViewOnceReceipts.CountAsync());
        Assert.Empty(await db.ViewOnceMediaSessions.ToListAsync());
    }
}
