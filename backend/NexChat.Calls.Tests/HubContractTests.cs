using System.Buffers;
using System.Reflection;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.SignalR;
using Microsoft.AspNetCore.SignalR.Protocol;
using NexChat.API.Hubs;

static class HubContractTests
{
    public static void Run()
    {
        var room = Guid.NewGuid().ToString(); var call = Guid.NewGuid().ToString();
        var contracts = new (Type Hub, string Method, object[] Args)[] {
            (typeof(ConversationHub), "RequestVideoCallV2", [room, false, call]),
            (typeof(ConversationHub), "AcceptVideoCallV2", [room, call]),
            (typeof(ConversationHub), "DeclineVideoCallV2", [room, true, "busy", call]),
            (typeof(ConversationHub), "EndVideoCallV2", [room, 10, call]),
            (typeof(ConversationHub), "NotifyVideoCallRingingV2", [room, call]),
            (typeof(ConversationHub), "ReleaseVideoCallBusyV2", [room, call]),
            (typeof(ConversationHub), "HeartbeatVideoCall", [room, call]),
            (typeof(ChatHub), "RequestVideoCallV2", [room, false, call]),
            (typeof(ChatHub), "AcceptVideoCallV2", [room, call]),
            (typeof(ChatHub), "DeclineVideoCallV2", [room, "cancelled", call]),
            (typeof(ChatHub), "EndVideoCallV2", [room, 10, call]),
            (typeof(ChatHub), "HeartbeatVideoCall", [room, call]),
        };
        foreach (var (hub, method, arguments) in contracts)
        {
            var json = JsonSerializer.Serialize(new { type = 1, target = method, arguments }) + "\u001e";
            var input = new ReadOnlySequence<byte>(Encoding.UTF8.GetBytes(json));
            if (!new JsonHubProtocol().TryParseMessage(ref input, new ReflectionBinder(hub), out var message) || message is not InvocationMessage)
                throw new Exception($"SignalR binding failed for {hub.Name}.{method}: {message?.GetType().Name}");
        }
        Console.WriteLine("PASS all 12 V2 call wire contracts bind with actual ASP.NET SignalR JSON protocol");
    }
    private sealed class ReflectionBinder(Type hub) : IInvocationBinder
    {
        public IReadOnlyList<Type> GetParameterTypes(string methodName) => hub.GetMethod(methodName)!.GetParameters().Select(p => p.ParameterType).ToArray();
        public Type GetReturnType(string invocationId) => typeof(object);
        public Type GetStreamItemType(string streamId) => typeof(object);
    }
}
