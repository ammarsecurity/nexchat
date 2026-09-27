using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NexChat.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddViewOnceMedia : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "IsViewOnce",
                table: "ConversationMessages",
                type: "tinyint(1)",
                nullable: false,
                defaultValue: false);

            migrationBuilder.CreateTable(
                name: "ViewOnceReceipts",
                columns: table => new
                {
                    MessageId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                    UserId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                    ViewedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ViewOnceReceipts", x => new { x.MessageId, x.UserId });
                    table.ForeignKey(
                        name: "FK_ViewOnceReceipts_ConversationMessages_MessageId",
                        column: x => x.MessageId,
                        principalTable: "ConversationMessages",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_ViewOnceReceipts_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "IX_ViewOnceReceipts_UserId",
                table: "ViewOnceReceipts",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ViewOnceReceipts");

            migrationBuilder.DropColumn(
                name: "IsViewOnce",
                table: "ConversationMessages");
        }
    }
}
