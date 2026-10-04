import Foundation
import PushKit
import UIKit

/// PushKit VoIP — wakes the app when killed so CallKit can present the incoming call.
final class VoipPushManager: NSObject, PKPushRegistryDelegate {
  static let shared = VoipPushManager()

  private static let tokenKey = "nexchat_voip_token"
  private static let userKey = "nexchat_push_user"
  var currentToken: String? { UserDefaults.standard.string(forKey: Self.tokenKey) }
  var authenticatedUser: String? { UserDefaults.standard.string(forKey: Self.userKey) }

  func setAuthenticatedUser(_ userId: String?) {
    let previous = authenticatedUser
    UserDefaults.standard.set(userId, forKey: Self.userKey)
    if userId == nil || previous != userId {
      IncomingCallKit.shared.stop()
    }
  }

  private var registry: PKPushRegistry?
  private weak var channel: FlutterMethodChannel?

  func start(channel: FlutterMethodChannel) {
    self.channel = channel
    let reg = PKPushRegistry(queue: DispatchQueue.main)
    reg.delegate = self
    reg.desiredPushTypes = [.voIP]
    registry = reg
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    UserDefaults.standard.set(token, forKey: Self.tokenKey)
    DispatchQueue.main.async {
      self.channel?.invokeMethod("voipToken", arguments: ["token": token])
    }
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    // Retain an explicit empty value until the server revocation can be replayed.
    UserDefaults.standard.set("", forKey: Self.tokenKey)
    channel?.invokeMethod("voipToken", arguments: ["token": ""])
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    let root = payload.dictionaryPayload
    let data = (root["data"] as? [String: Any]) ?? root
    let callId = data["callId"] as? String
    let recipient = data["recipientUserId"] as? String
    let conversationId = (data["conversationId"] as? String)
    let sessionId = (data["sessionId"] as? String)
    let voiceOnly = "\(data["voiceOnly"] ?? "")" == "true"
    let callerName = (data["callerName"] as? String) ?? "NexChat"
    let callerAvatar = data["callerAvatar"] as? String
    let pushType = "\(data["type"] ?? "")"

    // Current servers never send cancellation via PushKit. Any legacy, stale-account,
    // malformed or disabled push must still satisfy iOS's CallKit reporting contract,
    // without exposing caller data or disturbing an unrelated active call.
    guard pushType == "video_call",
          let user = authenticatedUser, !user.isEmpty,
          recipient == user,
          let callId, UUID(uuidString: callId) != nil else {
      IncomingCallKit.shared.reportUnavailableVoip(completion: completion)
      return
    }

    IncomingCallKit.shared.showIncomingFromVoip(
      callId: callId,
      conversationId: conversationId,
      sessionId: sessionId,
      voiceOnly: voiceOnly,
      callerName: callerName,
      callerAvatar: callerAvatar,
      completion: completion
    )
  }
}
