using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NexChat.Infrastructure.Migrations
{
    public partial class AddUserCoverImage : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "CoverImageUrl",
                table: "Users",
                type: "longtext",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "CoverImageUrl",
                table: "Users");
        }
    }
}
