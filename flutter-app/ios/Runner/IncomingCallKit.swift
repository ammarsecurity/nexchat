import CallKit
import AVFoundation
import Foundation

/// CallKit + pending-call store for iOS (mirrors Android FSI / IncomingCallStore).
final class IncomingCallKit: NSObject, CXProviderDelegate {
  static let shared = IncomingCallKit()

  private let provider: CXProvider
  private let controller = CXCallController()
  private var activeUUID: UUID?
  private var ringTimeout: DispatchWorkItem?
  private weak var channel: FlutterMethodChannel?

  private(set) var flutterReady = false
  private var appForeground = false

  private enum Pref {
    static let suite = UserDefaults.standard
    static let conversationId = "nexchat_incoming_conversation_id"
    static let sessionId = "nexchat_incoming_session_id"
    static let voiceOnly = "nexchat_incoming_voice_only"
    static let callerName = "nexchat_incoming_caller_name"
    static let callerAvatar = "nexchat_incoming_caller_avatar"
    static let action = "nexchat_incoming_action"
  }

  private override init() {
    let config = CXProviderConfiguration()
    config.supportsVideo = true
    config.maximumCallsPerCallGroup = 1
    config.maximumCallGroups = 1
    config.supportedHandleTypes = [.generic]
    if #available(iOS 14.0, *) {
      config.includesCallsInRecents = false
    }
    provider = CXProvider(configuration: config)
    super.init()
    provider.setDelegate(self, queue: nil)
  }

  func attach(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  func markReady() {
    flutterReady = true
    notifyFlutterIfReady()
  }

  func setForeground(_ value: Bool) {
    appForeground = value
  }

  /// PushKit path: report CallKit first, then invoke completion (required by iOS).
  func showIncomingFromVoip(
    conversationId: String?,
    sessionId: String?,
    voiceOnly: Bool,
    callerName: String,
    callerAvatar: String?,
    completion: @escaping () -> Void
  ) {
    save(
      conversationId: conversationId,
      sessionId: sessionId,
      voiceOnly: voiceOnly,
      callerName: callerName,
      callerAvatar: callerAvatar,
      action: "ring"
    )
    endActiveCallKit(report: false)

    let uuid = UUID()
    activeUUID = uuid
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: callerName.isEmpty ? "NexChat" : callerName)
    update.localizedCallerName = callerName.isEmpty ? "NexChat" : callerName
    update.hasVideo = !voiceOnly
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false

    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      if let error {
        NSLog("[CallKit] VoIP report failed: %@", error.localizedDescription)
      } else {
        self?.scheduleRingTimeout()
      }
      completion()
      self?.notifyFlutterIfReady()
    }
  }

  func showIncoming(
    conversationId: String?,
    sessionId: String?,
    voiceOnly: Bool,
    callerName: String,
    callerAvatar: String?
  ) {
    save(
      conversationId: conversationId,
      sessionId: sessionId,
      voiceOnly: voiceOnly,
      callerName: callerName,
      callerAvatar: callerAvatar,
      action: "ring"
    )

    // If Flutter is already foreground + ready, the in-app overlay handles UI.
    if flutterReady && appForeground {
      notifyFlutterIfReady()
      return
    }

    endActiveCallKit(report: false)

    let uuid = UUID()
    activeUUID = uuid
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: callerName.isEmpty ? "NexChat" : callerName)
    update.localizedCallerName = callerName.isEmpty ? "NexChat" : callerName
    update.hasVideo = !voiceOnly
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false

    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      if let error {
        NSLog("[CallKit] reportNewIncomingCall failed: %@", error.localizedDescription)
        self?.notifyFlutterIfReady()
        return
      }
      self?.scheduleRingTimeout()
    }
  }

  func dismissIncoming(clearStore: Bool = true) {
    cancelRingTimeout()
    endActiveCallKit(report: true)
    if clearStore {
      clear()
    }
  }

  func consumePending() -> [String: Any]? {
    let data = peek()
    if data != nil { clear() }
    return data
  }

  // MARK: - CXProviderDelegate

  func providerDidReset(_ provider: CXProvider) {
    activeUUID = nil
    cancelRingTimeout()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    cancelRingTimeout()
    configureAudioSession()
    action.fulfill()
    mutateAction("accept")
    notifyFlutterIfReady()
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    cancelRingTimeout()
    let uuid = action.callUUID
    action.fulfill()
    if activeUUID == uuid {
      activeUUID = nil
    }
    guard let current = peek() else { return }
    let actionName = (current["action"] as? String) ?? "ring"
    // Decline / miss if still ringing (not accepted into media yet).
    if actionName == "ring" || actionName == "decline" {
      mutateAction("decline")
      CallDeclineHttpIOS.declineAsync(
        conversationId: current["conversationId"] as? String,
        outcome: "declined"
      )
      notifyFlutterIfReady()
    } else {
      clear()
    }
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    // LiveKit / Flutter will take over the session once connected.
  }

  // MARK: - Private

  private func scheduleRingTimeout() {
    cancelRingTimeout()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.mutateAction("decline")
      let cid = self.peek()?["conversationId"] as? String
      CallDeclineHttpIOS.declineAsync(conversationId: cid, outcome: "missed")
      self.endActiveCallKit(report: true)
      self.notifyFlutterIfReady()
    }
    ringTimeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
  }

  private func cancelRingTimeout() {
    ringTimeout?.cancel()
    ringTimeout = nil
  }

  private func endActiveCallKit(report: Bool) {
    guard let uuid = activeUUID else { return }
    activeUUID = nil
    if report {
      provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
    }
    let end = CXEndCallAction(call: uuid)
    let tx = CXTransaction(action: end)
    controller.request(tx) { _ in }
  }

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
    try? session.setActive(true)
  }

  private func notifyFlutterIfReady() {
    guard flutterReady else { return }
    guard let data = consumePending() else { return }
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("incomingEvent", arguments: data)
    }
  }

  private func save(
    conversationId: String?,
    sessionId: String?,
    voiceOnly: Bool,
    callerName: String,
    callerAvatar: String?,
    action: String
  ) {
    let d = Pref.suite
    d.set(conversationId ?? "", forKey: Pref.conversationId)
    d.set(sessionId ?? "", forKey: Pref.sessionId)
    d.set(voiceOnly, forKey: Pref.voiceOnly)
    d.set(callerName, forKey: Pref.callerName)
    d.set(callerAvatar ?? "", forKey: Pref.callerAvatar)
    d.set(action, forKey: Pref.action)
  }

  private func mutateAction(_ action: String) {
    Pref.suite.set(action, forKey: Pref.action)
  }

  private func peek() -> [String: Any]? {
    let d = Pref.suite
    let conversationId = d.string(forKey: Pref.conversationId) ?? ""
    let sessionId = d.string(forKey: Pref.sessionId) ?? ""
    if conversationId.isEmpty && sessionId.isEmpty { return nil }
    var map: [String: Any] = [
      "conversationId": conversationId.isEmpty ? NSNull() : conversationId,
      "sessionId": sessionId.isEmpty ? NSNull() : sessionId,
      "voiceOnly": d.bool(forKey: Pref.voiceOnly),
      "callerName": d.string(forKey: Pref.callerName) ?? "",
      "action": d.string(forKey: Pref.action) ?? "ring",
    ]
    let avatar = d.string(forKey: Pref.callerAvatar) ?? ""
    map["callerAvatar"] = avatar.isEmpty ? NSNull() : avatar
    return map
  }

  private func clear() {
    let d = Pref.suite
    d.removeObject(forKey: Pref.conversationId)
    d.removeObject(forKey: Pref.sessionId)
    d.removeObject(forKey: Pref.voiceOnly)
    d.removeObject(forKey: Pref.callerName)
    d.removeObject(forKey: Pref.callerAvatar)
    d.removeObject(forKey: Pref.action)
  }
}

/// REST decline when Flutter engine is not ready (matches Android CallDeclineHttp).
enum CallDeclineHttpIOS {
  static func declineAsync(conversationId: String?, outcome: String) {
    guard let conversationId, !conversationId.isEmpty else { return }
    DispatchQueue.global(qos: .utility).async {
      decline(conversationId: conversationId, outcome: outcome)
    }
  }

  private static func decline(conversationId: String, outcome: String) {
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
    let body: [String: Any] = [
      "conversationId": conversationId,
      "busy": false,
      "outcome": outcome,
    ]
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
