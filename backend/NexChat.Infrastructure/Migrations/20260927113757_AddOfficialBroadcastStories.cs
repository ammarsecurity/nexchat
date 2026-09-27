using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NexChat.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddOfficialBroadcastStories : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "IsOfficialStoryPublisher",
                table: "Users",
                type: "tinyint(1)",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "IsBroadcast",
                table: "StorySlides",
                type: "tinyint(1)",
                nullable: false,
                defaultValue: false);

            migrationBuilder.CreateIndex(
                name: "IX_StorySlides_IsBroadcast_ExpiresAt",
                table: "StorySlides",
                columns: new[] { "IsBroadcast", "ExpiresAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_StorySlides_IsBroadcast_ExpiresAt",
                table: "StorySlides");

            migrationBuilder.DropColumn(
                name: "IsOfficialStoryPublisher",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "IsBroadcast",
                table: "StorySlides");
        }
    }
}
