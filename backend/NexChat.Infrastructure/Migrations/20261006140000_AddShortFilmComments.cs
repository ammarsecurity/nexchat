using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using NexChat.Infrastructure.Data;

#nullable disable

namespace NexChat.Infrastructure.Migrations;

[DbContext(typeof(AppDbContext))]
[Migration("20261006140000_AddShortFilmComments")]
public class AddShortFilmComments : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "ShortFilmComments",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                ShortFilmId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                UserId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                Body = table.Column<string>(type: "varchar(300)", maxLength: 300, nullable: false)
                    .Annotation("MySql:CharSet", "utf8mb4"),
                IsHidden = table.Column<bool>(type: "tinyint(1)", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ShortFilmComments", x => x.Id);
                table.ForeignKey(
                    name: "FK_ShortFilmComments_ShortFilms_ShortFilmId",
                    column: x => x.ShortFilmId,
                    principalTable: "ShortFilms",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_ShortFilmComments_Users_UserId",
                    column: x => x.UserId,
                    principalTable: "Users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            })
            .Annotation("MySql:CharSet", "utf8mb4");

        migrationBuilder.CreateTable(
            name: "ShortFilmCommentReports",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                CommentId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                ReporterId = table.Column<Guid>(type: "char(36)", nullable: false, collation: "ascii_general_ci"),
                Reason = table.Column<string>(type: "varchar(200)", maxLength: 200, nullable: false)
                    .Annotation("MySql:CharSet", "utf8mb4"),
                IsReviewed = table.Column<bool>(type: "tinyint(1)", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_ShortFilmCommentReports", x => x.Id);
                table.ForeignKey(
                    name: "FK_ShortFilmCommentReports_ShortFilmComments_CommentId",
                    column: x => x.CommentId,
                    principalTable: "ShortFilmComments",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
                table.ForeignKey(
                    name: "FK_ShortFilmCommentReports_Users_ReporterId",
                    column: x => x.ReporterId,
                    principalTable: "Users",
                    principalColumn: "Id",
                    onDelete: ReferentialAction.Cascade);
            })
            .Annotation("MySql:CharSet", "utf8mb4");

        migrationBuilder.CreateIndex(
            name: "IX_ShortFilmComments_ShortFilmId_IsHidden_CreatedAt",
            table: "ShortFilmComments",
            columns: new[] { "ShortFilmId", "IsHidden", "CreatedAt" });
        migrationBuilder.CreateIndex(
            name: "IX_ShortFilmComments_UserId_CreatedAt",
            table: "ShortFilmComments",
            columns: new[] { "UserId", "CreatedAt" });
        migrationBuilder.CreateIndex(
            name: "IX_ShortFilmCommentReports_CommentId_ReporterId",
            table: "ShortFilmCommentReports",
            columns: new[] { "CommentId", "ReporterId" },
            unique: true);
        migrationBuilder.CreateIndex(
            name: "IX_ShortFilmCommentReports_IsReviewed_CreatedAt",
            table: "ShortFilmCommentReports",
            columns: new[] { "IsReviewed", "CreatedAt" });
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropTable(name: "ShortFilmCommentReports");
        migrationBuilder.DropTable(name: "ShortFilmComments");
    }
}
