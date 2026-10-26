using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using NexChat.Infrastructure.Data;

#nullable disable

namespace NexChat.Infrastructure.Migrations;

[DbContext(typeof(AppDbContext))]
[Migration("20261026120000_AddDiscoverSwipesAndMatches")]
public class AddDiscoverSwipesAndMatches : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "UserSwipes",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                FromUserId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                ToUserId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                Direction = table.Column<string>(type: "varchar(10)", maxLength: 10, nullable: false)
                    .Annotation("MySql:CharSet", "utf8mb4"),
                CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_UserSwipes", x => x.Id);
                table.ForeignKey(
                    name: "FK_UserSwipes_Users_FromUserId",
                    column: x => x.FromUserId,
                    principalTable: "Users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_UserSwipes_Users_ToUserId",
                    column: x => x.ToUserId,
                    principalTable: "Users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            })
            .Annotation("MySql:CharSet", "utf8mb4");

        migrationBuilder.CreateTable(
            name: "UserMatches",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                UserAId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                UserBId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                ConversationId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_UserMatches", x => x.Id);
                table.ForeignKey(
                    name: "FK_UserMatches_Users_UserAId",
                    column: x => x.UserAId,
                    principalTable: "Users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_UserMatches_Users_UserBId",
                    column: x => x.UserBId,
                    principalTable: "Users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_UserMatches_Conversations_ConversationId",
                    column: x => x.ConversationId,
                    principalTable: "Conversations",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            })
            .Annotation("MySql:CharSet", "utf8mb4");

        migrationBuilder.CreateIndex(
            name: "IX_UserSwipes_FromUserId_ToUserId",
            table: "UserSwipes",
            columns: new[] { "FromUserId", "ToUserId" },
            unique: true);
        migrationBuilder.CreateIndex(
            name: "IX_UserSwipes_ToUserId_Direction_CreatedAt",
            table: "UserSwipes",
            columns: new[] { "ToUserId", "Direction", "CreatedAt" });

        migrationBuilder.CreateIndex(
            name: "IX_UserMatches_UserAId_UserBId",
            table: "UserMatches",
            columns: new[] { "UserAId", "UserBId" },
            unique: true);
        migrationBuilder.CreateIndex(
            name: "IX_UserMatches_ConversationId",
            table: "UserMatches",
            column: "ConversationId");
        migrationBuilder.CreateIndex(
            name: "IX_UserMatches_CreatedAt",
            table: "UserMatches",
            column: "CreatedAt");

        // App Store launch: disable Omegle-style random chat and code connect; enable Discover.
        migrationBuilder.Sql("""
            INSERT INTO SiteContents (Id, `Key`, Content, UpdatedAt)
            SELECT UUID(), 'random_chat_enabled', 'false', UTC_TIMESTAMP(6)
            FROM DUAL
            WHERE NOT EXISTS (SELECT 1 FROM SiteContents WHERE `Key` = 'random_chat_enabled');
            UPDATE SiteContents SET Content = 'false', UpdatedAt = UTC_TIMESTAMP(6)
            WHERE `Key` = 'random_chat_enabled';
            """);
        migrationBuilder.Sql("""
            INSERT INTO SiteContents (Id, `Key`, Content, UpdatedAt)
            SELECT UUID(), 'code_connect_features_enabled', 'false', UTC_TIMESTAMP(6)
            FROM DUAL
            WHERE NOT EXISTS (SELECT 1 FROM SiteContents WHERE `Key` = 'code_connect_features_enabled');
            UPDATE SiteContents SET Content = 'false', UpdatedAt = UTC_TIMESTAMP(6)
            WHERE `Key` = 'code_connect_features_enabled';
            """);
        migrationBuilder.Sql("""
            INSERT INTO SiteContents (Id, `Key`, Content, UpdatedAt)
            SELECT UUID(), 'discover_swipe_enabled', 'true', UTC_TIMESTAMP(6)
            FROM DUAL
            WHERE NOT EXISTS (SELECT 1 FROM SiteContents WHERE `Key` = 'discover_swipe_enabled');
            UPDATE SiteContents SET Content = 'true', UpdatedAt = UTC_TIMESTAMP(6)
            WHERE `Key` = 'discover_swipe_enabled';
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "UserMatches");
        migrationBuilder.DropTable(name: "UserSwipes");
    }
}
