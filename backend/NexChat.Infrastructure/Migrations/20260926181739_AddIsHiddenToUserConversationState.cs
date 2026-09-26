using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NexChat.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddIsHiddenToUserConversationState : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "IsHidden",
                table: "UserConversationStates",
                type: "tinyint(1)",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "IsHidden",
                table: "UserConversationStates");
        }
    }
}
