using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using NexChat.Infrastructure.Data;

#nullable disable

namespace NexChat.Infrastructure.Migrations;

[DbContext(typeof(AppDbContext))]
[Migration("20261028120000_AddUserDiscoverEnabled")]
public class AddUserDiscoverEnabled : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<bool>(
            name: "DiscoverEnabled",
            table: "Users",
            type: "tinyint(1)",
            nullable: false,
            defaultValue: false);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(name: "DiscoverEnabled", table: "Users");
    }
}
