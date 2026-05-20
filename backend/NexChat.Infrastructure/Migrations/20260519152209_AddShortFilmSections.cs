using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NexChat.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddShortFilmSections : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<Guid>(
                name: "SectionId",
                table: "ShortFilms",
                type: "char(36)",
                nullable: true,
                collation: "ascii_general_ci");

            migrationBuilder.CreateTable(
                name: "ShortFilmSections",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                    Name = table.Column<string>(type: "varchar(120)", maxLength: 120, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    SortOrder = table.Column<int>(type: "int", nullable: false),
                    IsActive = table.Column<bool>(type: "tinyint(1)", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ShortFilmSections", x => x.Id);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "IX_ShortFilms_SectionId_IsActive_SortOrder",
                table: "ShortFilms",
                columns: new[] { "SectionId", "IsActive", "SortOrder" });

            migrationBuilder.CreateIndex(
                name: "IX_ShortFilmSections_IsActive_SortOrder",
                table: "ShortFilmSections",
                columns: new[] { "IsActive", "SortOrder" });

            migrationBuilder.AddForeignKey(
                name: "FK_ShortFilms_ShortFilmSections_SectionId",
                table: "ShortFilms",
                column: "SectionId",
                principalTable: "ShortFilmSections",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ShortFilms_ShortFilmSections_SectionId",
                table: "ShortFilms");

            migrationBuilder.DropTable(
                name: "ShortFilmSections");

            migrationBuilder.DropIndex(
                name: "IX_ShortFilms_SectionId_IsActive_SortOrder",
                table: "ShortFilms");

            migrationBuilder.DropColumn(
                name: "SectionId",
                table: "ShortFilms");
        }
    }
}
