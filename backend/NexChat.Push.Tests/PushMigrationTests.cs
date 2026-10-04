using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using MySqlConnector;
using NexChat.Infrastructure.Data;
using Xunit;

namespace NexChat.Push.Tests;

public class PushMigrationTests
{
    [Fact]
    public void PushMigrationIsDiscoverableAndProviderEnablesUserVariables()
    {
        // Explicit server version prevents any connection or autodetect request.
        using var db = new AppDbContext(new DbContextOptionsBuilder<AppDbContext>()
            .UseMySql("Server=127.0.0.1;Database=push_test;User Id=test;", new MySqlServerVersion(new Version(8, 0, 21)))
            .Options);
        Assert.Contains("20261004172100_BindPushToInstallation", db.Database.GetMigrations());
        var connection = new MySqlConnectionStringBuilder(db.Database.GetDbConnection().ConnectionString);
        Assert.True(connection.AllowUserVariables);
        var script = db.GetService<IMigrator>().GenerateScript(
            "20260928122538_AddOfficialChatBroadcasts", "20261004172100_BindPushToInstallation");
        Assert.Contains("information_schema.COLUMNS", script);
        Assert.Contains("PREPARE nexchat_voip_stmt", script);
        Assert.Contains("CREATE UNIQUE INDEX `IX_DeviceSubscriptions_InstallationId`", script);
        Assert.DoesNotContain("ADD COLUMN IF NOT EXISTS", script);
    }
}
