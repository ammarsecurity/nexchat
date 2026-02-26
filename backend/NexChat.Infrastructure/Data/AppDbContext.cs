using Microsoft.EntityFrameworkCore;
using NexChat.Core.Entities;

namespace NexChat.Infrastructure.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<ChatSession> ChatSessions => Set<ChatSession>();
    public DbSet<Message> Messages => Set<Message>();
    public DbSet<Report> Reports => Set<Report>();
    public DbSet<Banner> Banners => Set<Banner>();
    public DbSet<SiteContent> SiteContents => Set<SiteContent>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<User>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Name).IsUnique();
            e.HasIndex(x => x.UniqueCode).IsUnique();
            e.Property(x => x.Name).HasMaxLength(50);
            e.Property(x => x.UniqueCode).HasMaxLength(10);
            e.Property(x => x.Gender).HasMaxLength(10);
        });

        modelBuilder.Entity<ChatSession>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.User1)
                .WithMany(u => u.SessionsAsUser1)
                .HasForeignKey(x => x.User1Id)
                .OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.User2)
                .WithMany(u => u.SessionsAsUser2)
                .HasForeignKey(x => x.User2Id)
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<Message>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Session)
                .WithMany(s => s.Messages)
                .HasForeignKey(x => x.SessionId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Sender)
                .WithMany()
                .HasForeignKey(x => x.SenderId)
                .OnDelete(DeleteBehavior.Restrict);
            e.Property(x => x.Content).HasMaxLength(2000);
        });

        modelBuilder.Entity<Report>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Reporter)
                .WithMany(u => u.ReportsGiven)
                .HasForeignKey(x => x.ReporterId)
                .OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Reported)
                .WithMany(u => u.ReportsReceived)
                .HasForeignKey(x => x.ReportedId)
                .OnDelete(DeleteBehavior.Restrict);
            e.Property(x => x.Reason).HasMaxLength(500);
        });

        modelBuilder.Entity<Banner>(e =>
        {
            e.HasKey(x => x.Id);
            e.Property(x => x.ImageUrl).HasMaxLength(500);
            e.Property(x => x.Placement).HasMaxLength(20);
            e.Property(x => x.Link).HasMaxLength(500);
        });

        modelBuilder.Entity<SiteContent>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Key).IsUnique();
            e.Property(x => x.Key).HasMaxLength(50);
        });
    }
}
