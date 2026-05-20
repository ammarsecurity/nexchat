using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NexChat.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddShortFilmStockSource : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "StockExternalId",
                table: "ShortFilms",
                type: "varchar(64)",
                maxLength: 64,
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<string>(
                name: "StockProvider",
                table: "ShortFilms",
                type: "varchar(20)",
                maxLength: 20,
                nullable: true)
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.CreateIndex(
                name: "IX_ShortFilms_StockProvider_StockExternalId",
                table: "ShortFilms",
                columns: new[] { "StockProvider", "StockExternalId" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_ShortFilms_StockProvider_StockExternalId",
                table: "ShortFilms");

            migrationBuilder.DropColumn(
                name: "StockExternalId",
                table: "ShortFilms");

            migrationBuilder.DropColumn(
                name: "StockProvider",
                table: "ShortFilms");
        }
    }
}
