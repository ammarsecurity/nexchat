using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NexChat.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddShortFilmSeries : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "EpisodeNumber",
                table: "ShortFilms",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "SeriesId",
                table: "ShortFilms",
                type: "char(36)",
                nullable: true,
                collation: "ascii_general_ci");

            migrationBuilder.CreateTable(
                name: "ShortFilmSeries",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                    Title = table.Column<string>(type: "varchar(200)", maxLength: 200, nullable: false)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    Description = table.Column<string>(type: "varchar(1000)", maxLength: 1000, nullable: true)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    CoverUrl = table.Column<string>(type: "varchar(500)", maxLength: 500, nullable: true)
                        .Annotation("MySql:CharSet", "utf8mb4"),
                    SectionId = table.Column<Guid>(type: "char(36)", nullable: true, collation: "ascii_general_ci"),
                    SortOrder = table.Column<int>(type: "int", nullable: false),
                    IsActive = table.Column<bool>(type: "tinyint(1)", nullable: false),
                    IsFeatured = table.Column<bool>(type: "tinyint(1)", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ShortFilmSeries", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ShortFilmSeries_ShortFilmSections_SectionId",
                        column: x => x.SectionId,
                        principalTable: "ShortFilmSections",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                })
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "IX_ShortFilms_SeriesId_EpisodeNumber",
                table: "ShortFilms",
                columns: new[] { "SeriesId", "EpisodeNumber" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ShortFilms_SeriesId_IsActive_EpisodeNumber",
                table: "ShortFilms",
                columns: new[] { "SeriesId", "IsActive", "EpisodeNumber" });

            migrationBuilder.CreateIndex(
                name: "IX_ShortFilmSeries_IsActive_SortOrder",
                table: "ShortFilmSeries",
                columns: new[] { "IsActive", "SortOrder" });

            migrationBuilder.CreateIndex(
                name: "IX_ShortFilmSeries_IsFeatured_IsActive",
                table: "ShortFilmSeries",
                columns: new[] { "IsFeatured", "IsActive" });

            migrationBuilder.CreateIndex(
                name: "IX_ShortFilmSeries_SectionId",
                table: "ShortFilmSeries",
                column: "SectionId");

            migrationBuilder.CreateIndex(
                name: "IX_ShortFilmSeries_Title",
                table: "ShortFilmSeries",
                column: "Title");

            migrationBuilder.AddForeignKey(
                name: "FK_ShortFilms_ShortFilmSeries_SeriesId",
                table: "ShortFilms",
                column: "SeriesId",
                principalTable: "ShortFilmSeries",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_ShortFilms_ShortFilmSeries_SeriesId",
                table: "ShortFilms");

            migrationBuilder.DropTable(
                name: "ShortFilmSeries");

            migrationBuilder.DropIndex(
                name: "IX_ShortFilms_SeriesId_EpisodeNumber",
                table: "ShortFilms");

            migrationBuilder.DropIndex(
                name: "IX_ShortFilms_SeriesId_IsActive_EpisodeNumber",
                table: "ShortFilms");

            migrationBuilder.DropColumn(
                name: "EpisodeNumber",
                table: "ShortFilms");

            migrationBuilder.DropColumn(
                name: "SeriesId",
                table: "ShortFilms");
        }
    }
}
