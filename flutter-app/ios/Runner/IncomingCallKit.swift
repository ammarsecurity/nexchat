import CallKit
import AVFoundation
import Foundation

/// Consumable events are separate from the active identity used by CallKit callbacks.
final class IncomingCallEventStore {
  private(set) var active: [String: Any]?
  private var pending = false
  func save(_ payload: [String: Any]) { active = payload; pending = true }
  func setAction(_ action: String, pending: Bool = true) {
    guard active != nil else { return }
    active?["action"] = action
    self.pending = pending
  }
  func consume() -> [String: Any]? {
    guard pending else { return nil }
    pending = false
    return active
  }
  func matches(_ callId: String?) -> Bool {
    guard let callId, !callId.isEmpty else { return false }
    return active?["callId"] as? String == callId
  }
  func clear() { active = nil; pending = false }
}

final class IncomingCallKit: NSObject, CXProviderDelegate {
  static let shared = IncomingCallKit()
  private let controller = CXCallController()
  private let provider: CXProvider
  private var ongoingCallId: String?
  private var activeUUID: UUID?
  private var ringTimeout: DispatchWorkItem?
  private weak var channel: FlutterMethodChannel?
  private let store = IncomingCallEventStore()
  private(set) var flutterReady = false
  private var appForeground = false

  private override init() {
    let config = CXProviderConfiguration()
    config.supportsVideo = true
    config.maximumCallsPerCallGroup = 1
    config.maximumCallGroups = 1
    config.supportedHandleTypes = [.generic]
    config.includesCallsInRecents = false
    provider = CXProvider(configuration: config)
    super.init()
    provider.setDelegate(self, queue: nil)
  }

  func attach(channel: FlutterMethodChannel) { self.channel = channel }
  func markReady() { flutterReady = true; notifyFlutterIfReady() }
  func setForeground(_ value: Bool) { appForeground = value }

  /// Satisfy PushKit's report requirement even for stale/legacy payloads, without caller PII.
  func reportUnavailableVoip(completion: @escaping () -> Void) {
    let uuid = UUID()
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: "NexChat")
    update.localizedCallerName = "NexChat"
    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] _ in
      self?.provider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
      completion()
    }
  }

  func showIncomingFromVoip(callId: String, conversationId: String?, sessionId: String?,
    voiceOnly: Bool, callerName: String, callerAvatar: String?, completion: @escaping () -> Void) {
    if let ongoingCallId, ongoingCallId != callId {
      reportUnavailableVoip(completion: completion)
      return
    }
    if store.matches(callId), let uuid = activeUUID {
      // Report each incoming PushKit delivery; don't replace the live call's identity/timer.
      provider.reportNewIncomingCall(with: uuid, update: update(voiceOnly, callerName)) { _ in completion() }
      return
    }
    // A second attempt must not end an already accepted call.
    if activeUUID != nil && store.active?["action"] as? String == "accept" {
      reportUnavailableVoip(completion: completion)
      return
    }
    replace(callId: callId, conversationId: conversationId, sessionId: sessionId,
            voiceOnly: voiceOnly, callerName: callerName, callerAvatar: callerAvatar)
    reportCurrent(voiceOnly, callerName, completion: completion)
  }

  func showIncoming(callId: String?, conversationId: String?, sessionId: String?,
    voiceOnly: Bool, callerName: String, callerAvatar: String?) {
    guard let callId, UUID(uuidString: callId) != nil,
          VoipPushManager.shared.authenticatedUser != nil else { return }
    if let ongoingCallId, ongoingCallId != callId { return }
    if store.matches(callId) { return }
    if activeUUID != nil && store.active?["action"] as? String == "accept" { return }
    replace(callId: callId, conversationId: conversationId, sessionId: sessionId,
            voiceOnly: voiceOnly, callerName: callerName, callerAvatar: callerAvatar)
    if flutterReady && appForeground {
      notifyFlutterIfReady()
      return
    }
    reportCurrent(voiceOnly, callerName, completion: {})
  }

  private func replace(callId: String, conversationId: String?, sessionId: String?,
    voiceOnly: Bool, callerName: String, callerAvatar: String?) {
    dismissIncoming()
    store.save([
      "callId": callId,
      "recipientUserId": VoipPushManager.shared.authenticatedUser as Any? ?? NSNull(),
      "conversationId": conversationId as Any? ?? NSNull(),
      "sessionId": sessionId as Any? ?? NSNull(),
      "voiceOnly": voiceOnly,
      "callerName": callerName,
      "callerAvatar": callerAvatar as Any? ?? NSNull(),
      "action": "ring",
    ])
  }

  private func update(_ voiceOnly: Bool, _ callerName: String) -> CXCallUpdate {
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: callerName.isEmpty ? "NexChat" : callerName)
    update.localizedCallerName = callerName.isEmpty ? "NexChat" : callerName
    update.hasVideo = !voiceOnly
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false
    return update
  }

  private func reportCurrent(_ voiceOnly: Bool, _ callerName: String, completion: @escaping () -> Void) {
    let uuid = UUID()
    activeUUID = uuid
    provider.reportNewIncomingCall(with: uuid, update: update(voiceOnly, callerName)) { [weak self] error in
      if let self, self.activeUUID == uuid {
        if error == nil { self.scheduleRingTimeout(uuid) }
        else { self.activeUUID = nil }
        self.notifyFlutterIfReady()
      }
      completion()
    }
  }

  func start(callId: String?) { ongoingCallId = callId }

  @discardableResult
  func stop(callId: String? = nil) -> Bool {
    if let callId, let ongoingCallId, callId != ongoingCallId { return false }
    ongoingCallId = nil
    dismissIncoming(clearStore: true, callId: callId)
    return true
  }

  func acceptIncoming(callId: String) {
    guard store.matches(callId) else { return }
    if store.active?["action"] as? String == "accept" { return }
    cancelRingTimeout()
    if let uuid = activeUUID {
      controller.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { _ in }
    } else {
      store.setAction("accept", pending: false)
    }
  }

  func dismissIncoming(clearStore: Bool = true, callId: String? = nil, reason: String? = nil) {
    if let callId, !store.matches(callId) { return }
    if reason == "answered" && store.active?["action"] as? String == "accept" { return }
    cancelRingTimeout()
    if let uuid = activeUUID {
      activeUUID = nil // Ignore a late CXEndCallAction for this replaced call.
      provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
    }
    if reason != nil {
      store.setAction("end")
      notifyFlutterIfReady()
    }
    if clearStore { store.clear() }
  }

  func consumePending() -> [String: Any]? { store.consume() }

  func providerDidReset(_ provider: CXProvider) {
    activeUUID = nil
    cancelRingTimeout()
    store.clear()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard action.callUUID == activeUUID else { action.fail(); return }
    cancelRingTimeout()
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
    action.fulfill()
    store.setAction("accept")
    notifyFlutterIfReady()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard action.callUUID == activeUUID else { action.fulfill(); return }
    activeUUID = nil
    cancelRingTimeout()
    action.fulfill()
    guard let current = store.active else { return }
    if current["action"] as? String == "ring" {
      store.setAction("decline")
      CallDeclineHttpIOS.declineAsync(conversationId: current["conversationId"] as? String,
        callId: current["callId"] as? String, sessionId: current["sessionId"] as? String, outcome: "declined")
    } else {
      store.setAction("end")
    }
    notifyFlutterIfReady()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}

  private func scheduleRingTimeout(_ uuid: UUID) {
    cancelRingTimeout()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.activeUUID == uuid, let current = self.store.active else { return }
      self.store.setAction("decline")
      CallDeclineHttpIOS.declineAsync(conversationId: current["conversationId"] as? String,
        callId: current["callId"] as? String, sessionId: current["sessionId"] as? String, outcome: "missed")
      self.dismissIncoming(clearStore: false)
      self.notifyFlutterIfReady()
    }
    ringTimeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
  }

  private func cancelRingTimeout() { ringTimeout?.cancel(); ringTimeout = nil }
  private func notifyFlutterIfReady() {
    guard flutterReady, let data = store.consume() else { return }
    // Provider and PushKit callbacks run on main; avoid delivering an old event later.
    channel?.invokeMethod("incomingEvent", arguments: data)
  }
}

/// REST decline when Flutter engine is not ready (matches Android CallDeclineHttp).
enum CallDeclineHttpIOS {
  static func declineAsync(conversationId: String?, callId: String?, sessionId: String? = nil, outcome: String) {
    guard let callId, !callId.isEmpty else { return }
    guard conversationId?.isEmpty == false || sessionId?.isEmpty == false else { return }
    DispatchQueue.global(qos: .utility).async {
      decline(conversationId: conversationId, callId: callId, sessionId: sessionId, outcome: outcome)
    }
  }

  private static func decline(conversationId: String?, callId: String, sessionId: String?, outcome: String) {
    let defaults = UserDefaults.standard
    // Flutter shared_preferences prefixes keys with "flutter."
    let token = (defaults.string(forKey: "flutter.nexchat_native_token") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let apiBase = (defaults.string(forKey: "flutter.nexchat_native_api") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty, !apiBase.isEmpty else {
      NSLog("[CallDeclineHttp] missing native auth mirror")
      return
    }
    let base = apiBase.hasSuffix("/") ? String(apiBase.dropLast()) : apiBase
    guard let url = URL(string: "\(base)/calls/signaling/decline") else { return }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.timeoutInterval = 12
    var body: [String: Any] = [
      "callId": callId,
      "busy": false,
      "outcome": outcome,
    ]
    if let conversationId, !conversationId.isEmpty { body["conversationId"] = conversationId }
    else if let sessionId { body["sessionId"] = sessionId }
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { _, response, error in
      if let error {
        NSLog("[CallDeclineHttp] %@", error.localizedDescription)
      } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        NSLog("[CallDeclineHttp] HTTP %d", http.statusCode)
      }
      sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 15)
  }
}
