using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using NexChat.Infrastructure.Data;

#nullable disable

namespace NexChat.Infrastructure.Migrations;

[DbContext(typeof(AppDbContext))]
[Migration("20261026190000_AddDiscoverBioAndPrefs")]
public class AddDiscoverBioAndPrefs : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string>(
            name: "Bio",
            table: "Users",
            type: "varchar(160)",
            maxLength: 160,
            nullable: true)
            .Annotation("MySql:CharSet", "utf8mb4");

        migrationBuilder.AddColumn<string>(
            name: "DiscoverPreferGender",
            table: "Users",
            type: "varchar(10)",
            maxLength: 10,
            nullable: false,
            defaultValue: "all")
            .Annotation("MySql:CharSet", "utf8mb4");

        migrationBuilder.AddColumn<int>(
            name: "DiscoverAgeMin",
            table: "Users",
            type: "int",
            nullable: false,
            defaultValue: 18);

        migrationBuilder.AddColumn<int>(
            name: "DiscoverAgeMax",
            table: "Users",
            type: "int",
            nullable: false,
            defaultValue: 60);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(name: "Bio", table: "Users");
        migrationBuilder.DropColumn(name: "DiscoverPreferGender", table: "Users");
        migrationBuilder.DropColumn(name: "DiscoverAgeMin", table: "Users");
        migrationBuilder.DropColumn(name: "DiscoverAgeMax", table: "Users");
    }
}
