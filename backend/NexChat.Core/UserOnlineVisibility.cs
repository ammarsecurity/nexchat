using NexChat.Core.Entities;

namespace NexChat.Core;

/// <summary>ما يراه الآخرون من حالة «متصل» (مع احترام إعداد الإخفاء).</summary>
public static class UserOnlineVisibility
{
    public static bool VisibleToOthers(User user) =>
        user.IsOnline && user.ShowOnlineStatusToOthers;
}
