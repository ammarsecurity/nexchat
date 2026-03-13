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
    public DbSet<DeviceSubscription> DeviceSubscriptions => Set<DeviceSubscription>();
    public DbSet<SavedCode> SavedCodes => Set<SavedCode>();
    public DbSet<CodeConnectionAttempt> CodeConnectionAttempts => Set<CodeConnectionAttempt>();
    public DbSet<Contact> Contacts => Set<Contact>();
    public DbSet<Conversation> Conversations => Set<Conversation>();
    public DbSet<ConversationMessage> ConversationMessages => Set<ConversationMessage>();
    public DbSet<UserMessageDeletion> UserMessageDeletions => Set<UserMessageDeletion>();
    public DbSet<UserConversationDeletion> UserConversationDeletions => Set<UserConversationDeletion>();
    public DbSet<UserConversationState> UserConversationStates => Set<UserConversationState>();
    public DbSet<UserBlock> UserBlocks => Set<UserBlock>();
    public DbSet<BroadcastNotificationHistory> BroadcastNotificationHistory => Set<BroadcastNotificationHistory>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<User>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Name).IsUnique();
            e.HasIndex(x => x.UniqueCode).IsUnique();
            e.HasIndex(x => x.PhoneNumber).IsUnique();
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

        modelBuilder.Entity<DeviceSubscription>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.User)
                .WithMany()
                .HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.UserId, x.OneSignalPlayerId }).IsUnique();
            e.Property(x => x.OneSignalPlayerId).HasMaxLength(64);
            e.Property(x => x.Platform).HasMaxLength(20);
        });

        modelBuilder.Entity<SavedCode>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.User)
                .WithMany()
                .HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.UserId, x.Code }).IsUnique();
            e.Property(x => x.Code).HasMaxLength(10);
            e.Property(x => x.Label).HasMaxLength(50);
        });

        modelBuilder.Entity<CodeConnectionAttempt>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Requester)
                .WithMany()
                .HasForeignKey(x => x.RequesterId)
                .OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.Target)
                .WithMany()
                .HasForeignKey(x => x.TargetId)
                .OnDelete(DeleteBehavior.Restrict);
            e.Property(x => x.Status).HasMaxLength(20);
            e.HasIndex(x => new { x.RequesterId, x.TargetId, x.CreatedAt });
        });

        modelBuilder.Entity<Contact>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.User)
                .WithMany()
                .HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.ContactUser)
                .WithMany()
                .HasForeignKey(x => x.ContactUserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.UserId, x.ContactUserId }).IsUnique();
        });

        modelBuilder.Entity<Conversation>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.User1)
                .WithMany()
                .HasForeignKey(x => x.User1Id)
                .OnDelete(DeleteBehavior.Restrict);
            e.HasOne(x => x.User2)
                .WithMany()
                .HasForeignKey(x => x.User2Id)
                .OnDelete(DeleteBehavior.Restrict);
            e.HasIndex(x => new { x.User1Id, x.User2Id }).IsUnique();
        });

        modelBuilder.Entity<ConversationMessage>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Conversation)
                .WithMany(c => c.Messages)
                .HasForeignKey(x => x.ConversationId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Sender)
                .WithMany()
                .HasForeignKey(x => x.SenderId)
                .OnDelete(DeleteBehavior.Restrict);
            e.Property(x => x.Content).HasMaxLength(5000);
            e.Property(x => x.Type).HasMaxLength(20);
        });

        modelBuilder.Entity<UserMessageDeletion>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.User)
                .WithMany()
                .HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Message)
                .WithMany()
                .HasForeignKey(x => x.MessageId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.UserId, x.MessageId }).IsUnique();
        });

        modelBuilder.Entity<UserConversationDeletion>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.User)
                .WithMany()
                .HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Conversation)
                .WithMany()
                .HasForeignKey(x => x.ConversationId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.UserId, x.ConversationId }).IsUnique();
        });

        modelBuilder.Entity<UserConversationState>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.User)
                .WithMany()
                .HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Conversation)
                .WithMany()
                .HasForeignKey(x => x.ConversationId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.UserId, x.ConversationId }).IsUnique();
        });

        modelBuilder.Entity<UserBlock>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Blocker)
                .WithMany()
                .HasForeignKey(x => x.BlockerId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.BlockedUser)
                .WithMany()
                .HasForeignKey(x => x.BlockedUserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.BlockerId, x.BlockedUserId }).IsUnique();
        });

        modelBuilder.Entity<BroadcastNotificationHistory>(e =>
        {
            e.HasKey(x => x.Id);
            e.Property(x => x.Title).HasMaxLength(100);
            e.Property(x => x.Body).HasMaxLength(500);
            e.Property(x => x.ImageUrl).HasMaxLength(500);
            e.HasIndex(x => x.SentAt);
        });
    }
}
