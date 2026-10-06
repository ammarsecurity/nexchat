using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using NexChat.Infrastructure.Data;

#nullable disable

namespace NexChat.Infrastructure.Migrations;

[DbContext(typeof(AppDbContext))]
[Migration("20261006120000_AddShortFilmEngagement")]
public class AddShortFilmEngagement : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<DateTime>(
            name: "ScheduledPublishAt",
            table: "ShortFilms",
            type: "datetime(6)",
            nullable: true);

        migrationBuilder.CreateTable(
            name: "ShortFilmLikes",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                ShortFilmId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                UserId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ShortFilmLikes", x => x.Id);
                table.ForeignKey(
                    name: "FK_ShortFilmLikes_ShortFilms_ShortFilmId",
                    column: x => x.ShortFilmId,
                    principalTable: "ShortFilms",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_ShortFilmLikes_Users_UserId",
                    column: x => x.UserId,
                    principalTable: "Users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            })
            .Annotation("MySql:CharSet", "utf8mb4");

        migrationBuilder.CreateTable(
            name: "ShortFilmWatchLaters",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                ShortFilmId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                UserId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ShortFilmWatchLaters", x => x.Id);
                table.ForeignKey(
                    name: "FK_ShortFilmWatchLaters_ShortFilms_ShortFilmId",
                    column: x => x.ShortFilmId,
                    principalTable: "ShortFilms",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_ShortFilmWatchLaters_Users_UserId",
                    column: x => x.UserId,
                    principalTable: "Users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            })
            .Annotation("MySql:CharSet", "utf8mb4");

        migrationBuilder.CreateTable(
            name: "ShortFilmReactions",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                ShortFilmId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                UserId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                Emoji = table.Column<string>(type: "varchar(16)", maxLength: 16, nullable: false)
                    .Annotation("MySql:CharSet", "utf8mb4"),
                CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ShortFilmReactions", x => x.Id);
                table.ForeignKey(
                    name: "FK_ShortFilmReactions_ShortFilms_ShortFilmId",
                    column: x => x.ShortFilmId,
                    principalTable: "ShortFilms",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_ShortFilmReactions_Users_UserId",
                    column: x => x.UserId,
                    principalTable: "Users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            })
            .Annotation("MySql:CharSet", "utf8mb4");

        migrationBuilder.CreateTable(
            name: "ShortFilmSeriesFollows",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                SeriesId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                UserId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ShortFilmSeriesFollows", x => x.Id);
                table.ForeignKey(
                    name: "FK_ShortFilmSeriesFollows_ShortFilmSeries_SeriesId",
                    column: x => x.SeriesId,
                    principalTable: "ShortFilmSeries",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_ShortFilmSeriesFollows_Users_UserId",
                    column: x => x.UserId,
                    principalTable: "Users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            })
            .Annotation("MySql:CharSet", "utf8mb4");

        migrationBuilder.CreateIndex(name: "IX_ShortFilmLikes_ShortFilmId_UserId", table: "ShortFilmLikes", columns: new[] { "ShortFilmId", "UserId" }, unique: true);
        migrationBuilder.CreateIndex(name: "IX_ShortFilmLikes_UserId_CreatedAt", table: "ShortFilmLikes", columns: new[] { "UserId", "CreatedAt" });
        migrationBuilder.CreateIndex(name: "IX_ShortFilmWatchLaters_ShortFilmId_UserId", table: "ShortFilmWatchLaters", columns: new[] { "ShortFilmId", "UserId" }, unique: true);
        migrationBuilder.CreateIndex(name: "IX_ShortFilmWatchLaters_UserId_CreatedAt", table: "ShortFilmWatchLaters", columns: new[] { "UserId", "CreatedAt" });
        migrationBuilder.CreateIndex(name: "IX_ShortFilmReactions_ShortFilmId_UserId", table: "ShortFilmReactions", columns: new[] { "ShortFilmId", "UserId" }, unique: true);
        migrationBuilder.CreateIndex(name: "IX_ShortFilmSeriesFollows_SeriesId_UserId", table: "ShortFilmSeriesFollows", columns: new[] { "SeriesId", "UserId" }, unique: true);
        migrationBuilder.CreateIndex(name: "IX_ShortFilmSeriesFollows_UserId_CreatedAt", table: "ShortFilmSeriesFollows", columns: new[] { "UserId", "CreatedAt" });
        migrationBuilder.CreateIndex(name: "IX_ShortFilms_ScheduledPublishAt", table: "ShortFilms", column: "ScheduledPublishAt");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "ShortFilmLikes");
        migrationBuilder.DropTable(name: "ShortFilmWatchLaters");
        migrationBuilder.DropTable(name: "ShortFilmReactions");
        migrationBuilder.DropTable(name: "ShortFilmSeriesFollows");
        migrationBuilder.DropIndex(name: "IX_ShortFilms_ScheduledPublishAt", table: "ShortFilms");
        migrationBuilder.DropColumn(name: "ScheduledPublishAt", table: "ShortFilms");
    }
}
