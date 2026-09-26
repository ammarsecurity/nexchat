using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NexChat.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddDisappearingMessages : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "DisappearMode",
                table: "Conversations",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "DisappearMode",
                table: "ConversationMessages",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateTime>(
                name: "ExpiresAt",
                table: "ConversationMessages",
                type: "datetime(6)",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "DisappearMode",
                table: "Conversations");

            migrationBuilder.DropColumn(
                name: "DisappearMode",
                table: "ConversationMessages");

            migrationBuilder.DropColumn(
                name: "ExpiresAt",
                table: "ConversationMessages");
        }
    }
}
