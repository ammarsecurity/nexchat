import Foundation
import PushKit
import UIKit

/// PushKit VoIP — wakes the app when killed so CallKit can present the incoming call.
final class VoipPushManager: NSObject, PKPushRegistryDelegate {
  static let shared = VoipPushManager()

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
    DispatchQueue.main.async {
      self.channel?.invokeMethod("voipToken", arguments: ["token": token])
    }
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    // Token invalidated — Flutter clears on next login.
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
    let conversationId = (data["conversationId"] as? String)
    let sessionId = (data["sessionId"] as? String)
    let voiceOnly = "\(data["voiceOnly"] ?? "")" == "true"
    let callerName = (data["callerName"] as? String) ?? "NexChat"
    let callerAvatar = data["callerAvatar"] as? String
    let pushType = "\(data["type"] ?? "")"

    if pushType == "call_cancel" {
      IncomingCallKit.shared.dismissIncoming(clearStore: true)
      completion()
      return
    }

    IncomingCallKit.shared.showIncomingFromVoip(
      conversationId: conversationId,
      sessionId: sessionId,
      voiceOnly: voiceOnly,
      callerName: callerName,
      callerAvatar: callerAvatar,
      completion: completion
    )
  }
}
