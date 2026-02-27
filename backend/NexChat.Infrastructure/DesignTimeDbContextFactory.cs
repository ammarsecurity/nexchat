using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;
using Pomelo.EntityFrameworkCore.MySql.Infrastructure;

namespace NexChat.Infrastructure.Data;

public class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        var config = new ConfigurationBuilder()
            .SetBasePath(Path.Combine(Directory.GetCurrentDirectory(), "../NexChat.API"))
            .AddJsonFile("appsettings.json", optional: true)
            .Build();

        var optionsBuilder = new DbContextOptionsBuilder<AppDbContext>();
        var conn = config.GetConnectionString("DefaultConnection")
            ?? "Server=localhost;Port=3306;Database=nexchat;User=root;Password=;";
        var serverVersion = new MySqlServerVersion(new Version(8, 0, 21));
        optionsBuilder.UseMySql(conn, serverVersion);

        return new AppDbContext(optionsBuilder.Options);
    }
}
