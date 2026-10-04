using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using NexChat.Infrastructure.Data;

#nullable disable

namespace NexChat.Infrastructure.Migrations;

[DbContext(typeof(AppDbContext))]
[Migration("20261004172100_BindPushToInstallation")]
public class BindPushToInstallation : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // The old VoIP migration lacked discovery metadata; some databases have this
        // column only from a manual ALTER. Reconcile both states before indexing it.
        migrationBuilder.Sql(@"
SET @nexchat_voip_sql = (SELECT IF(COUNT(*) = 0,
    'ALTER TABLE `DeviceSubscriptions` ADD COLUMN `VoipDeviceToken` varchar(200) NULL',
    'SELECT 1') FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'DeviceSubscriptions' AND COLUMN_NAME = 'VoipDeviceToken');
PREPARE nexchat_voip_stmt FROM @nexchat_voip_sql;
EXECUTE nexchat_voip_stmt;
DEALLOCATE PREPARE nexchat_voip_stmt;
");
        migrationBuilder.AddColumn<string>(name: "InstallationId", table: "DeviceSubscriptions", type: "varchar(36)", maxLength: 36, nullable: true);
        // Keep the most recent registration for each provider subscription before adding
        // global uniqueness. Legacy split VoIP rows converge on the next device refresh.
        migrationBuilder.Sql(@"
DELETE older FROM DeviceSubscriptions older
JOIN DeviceSubscriptions newer ON older.OneSignalPlayerId = newer.OneSignalPlayerId
AND (older.CreatedAt < newer.CreatedAt OR (older.CreatedAt = newer.CreatedAt AND older.Id < newer.Id));
UPDATE DeviceSubscriptions SET VoipDeviceToken = NULL WHERE VoipDeviceToken = '';
UPDATE DeviceSubscriptions older JOIN DeviceSubscriptions newer
ON older.VoipDeviceToken = newer.VoipDeviceToken
AND (older.CreatedAt < newer.CreatedAt OR (older.CreatedAt = newer.CreatedAt AND older.Id < newer.Id))
SET older.VoipDeviceToken = NULL;
");
        // Add a UserId index before removing the composite index used by the FK.
        migrationBuilder.CreateIndex("IX_DeviceSubscriptions_UserId", "DeviceSubscriptions", "UserId");
        migrationBuilder.DropIndex("IX_DeviceSubscriptions_UserId_OneSignalPlayerId", "DeviceSubscriptions");
        migrationBuilder.CreateIndex("IX_DeviceSubscriptions_OneSignalPlayerId", "DeviceSubscriptions", "OneSignalPlayerId", unique: true);
        migrationBuilder.CreateIndex("IX_DeviceSubscriptions_InstallationId", "DeviceSubscriptions", "InstallationId", unique: true);
        migrationBuilder.CreateIndex("IX_DeviceSubscriptions_VoipDeviceToken", "DeviceSubscriptions", "VoipDeviceToken", unique: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex("IX_DeviceSubscriptions_OneSignalPlayerId", "DeviceSubscriptions");
        migrationBuilder.DropIndex("IX_DeviceSubscriptions_InstallationId", "DeviceSubscriptions");
        migrationBuilder.DropIndex("IX_DeviceSubscriptions_VoipDeviceToken", "DeviceSubscriptions");
        migrationBuilder.CreateIndex("IX_DeviceSubscriptions_UserId_OneSignalPlayerId", "DeviceSubscriptions", new[] { "UserId", "OneSignalPlayerId" }, unique: true);
        migrationBuilder.DropIndex("IX_DeviceSubscriptions_UserId", "DeviceSubscriptions");
        migrationBuilder.DropColumn("InstallationId", "DeviceSubscriptions");
    }
}
