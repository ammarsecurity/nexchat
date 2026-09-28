using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NexChat.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddVoipDeviceToken : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Idempotent: column may already exist on prod from manual ALTER.
            migrationBuilder.Sql(@"
ALTER TABLE `DeviceSubscriptions`
  ADD COLUMN IF NOT EXISTS `VoipDeviceToken` varchar(200) NULL;
");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
ALTER TABLE `DeviceSubscriptions`
  DROP COLUMN IF EXISTS `VoipDeviceToken`;
");
        }
    }
}
