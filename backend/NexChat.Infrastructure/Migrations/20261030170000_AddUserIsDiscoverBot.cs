using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using NexChat.Infrastructure.Data;

#nullable disable

namespace NexChat.Infrastructure.Migrations;

[DbContext(typeof(AppDbContext))]
[Migration("20261030170000_AddUserIsDiscoverBot")]
public class AddUserIsDiscoverBot : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        // Idempotent: previous deploy may have added the column before FK table failed.
        migrationBuilder.Sql("""
            SET @db := DATABASE();
            SET @exists := (
              SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'Users' AND COLUMN_NAME = 'IsDiscoverBot'
            );
            SET @sql := IF(@exists = 0,
              'ALTER TABLE `Users` ADD `IsDiscoverBot` tinyint(1) NOT NULL DEFAULT FALSE',
              'SELECT 1');
            PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
            """);

        migrationBuilder.Sql("""
            SET @db := DATABASE();
            SET @exists := (
              SELECT COUNT(*) FROM information_schema.STATISTICS
              WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'Users'
                AND INDEX_NAME = 'IX_Users_IsDiscoverBot_Gender_DiscoverEnabled'
            );
            SET @sql := IF(@exists = 0,
              'CREATE INDEX `IX_Users_IsDiscoverBot_Gender_DiscoverEnabled` ON `Users` (`IsDiscoverBot`, `Gender`, `DiscoverEnabled`)',
              'SELECT 1');
            PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
            """);

        migrationBuilder.CreateTable(
            name: "DiscoverBotPhotoUsages",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                RelativePath = table.Column<string>(type: "varchar(260)", maxLength: 260, nullable: false)
                    .Annotation("MySql:CharSet", "utf8mb4"),
                Gender = table.Column<string>(type: "varchar(10)", maxLength: 10, nullable: false)
                    .Annotation("MySql:CharSet", "utf8mb4"),
                UserId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_DiscoverBotPhotoUsages", x => x.Id);
                table.ForeignKey(
                    name: "FK_DiscoverBotPhotoUsages_Users_UserId",
                    column: x => x.UserId,
                    principalTable: "Users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            })
            .Annotation("MySql:CharSet", "utf8mb4");

        migrationBuilder.CreateIndex(
            name: "IX_DiscoverBotPhotoUsages_RelativePath",
            table: "DiscoverBotPhotoUsages",
            column: "RelativePath",
            unique: true);

        migrationBuilder.CreateIndex(
            name: "IX_DiscoverBotPhotoUsages_UserId",
            table: "DiscoverBotPhotoUsages",
            column: "UserId");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "DiscoverBotPhotoUsages");
        migrationBuilder.Sql("""
            SET @db := DATABASE();
            SET @exists := (
              SELECT COUNT(*) FROM information_schema.STATISTICS
              WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'Users'
                AND INDEX_NAME = 'IX_Users_IsDiscoverBot_Gender_DiscoverEnabled'
            );
            SET @sql := IF(@exists > 0,
              'DROP INDEX `IX_Users_IsDiscoverBot_Gender_DiscoverEnabled` ON `Users`',
              'SELECT 1');
            PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
            """);
        migrationBuilder.Sql("""
            SET @db := DATABASE();
            SET @exists := (
              SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'Users' AND COLUMN_NAME = 'IsDiscoverBot'
            );
            SET @sql := IF(@exists > 0,
              'ALTER TABLE `Users` DROP COLUMN `IsDiscoverBot`',
              'SELECT 1');
            PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
            """);
    }
}
