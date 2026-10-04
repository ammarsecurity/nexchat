using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using NexChat.Infrastructure.Data;

namespace NexChat.Infrastructure.Migrations;

[DbContext(typeof(AppDbContext))]
[Migration("20261004172200_AddMessageClientIds")]
public class AddMessageClientIds : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string>(name: "ClientMessageId", table: "Messages", type: "varchar(80)", maxLength: 80, nullable: true, collation: "utf8mb4_bin");
        migrationBuilder.AddColumn<string>(name: "ClientMessageId", table: "ConversationMessages", type: "varchar(80)", maxLength: 80, nullable: true, collation: "utf8mb4_bin");
        migrationBuilder.AlterColumn<string>(name: "Content", table: "Messages", type: "varchar(5000)", maxLength: 5000, nullable: false, oldClrType: typeof(string), oldType: "varchar(2000)", oldMaxLength: 2000);
        migrationBuilder.CreateIndex(name: "IX_Messages_SessionId_SenderId_ClientMessageId", table: "Messages", columns: new[] { "SessionId", "SenderId", "ClientMessageId" }, unique: true);
        migrationBuilder.CreateIndex(name: "IX_ConversationMessages_ConversationId_SenderId_ClientMessageId", table: "ConversationMessages", columns: new[] { "ConversationId", "SenderId", "ClientMessageId" }, unique: true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropIndex(name: "IX_Messages_SessionId_SenderId_ClientMessageId", table: "Messages");
        migrationBuilder.DropIndex(name: "IX_ConversationMessages_ConversationId_SenderId_ClientMessageId", table: "ConversationMessages");
        migrationBuilder.DropColumn(name: "ClientMessageId", table: "Messages");
        migrationBuilder.DropColumn(name: "ClientMessageId", table: "ConversationMessages");
        // Keep the wider content column: shrinking could destroy accepted message data.
    }
}
