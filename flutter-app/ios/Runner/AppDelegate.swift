import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var secureOverlay: UIView?
  private var captureObserver: NSObjectProtocol?
  private var screenshotObserver: NSObjectProtocol?
  private var secureEnabled = false
  private var secureChannel: FlutterMethodChannel?
  private var callChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NexChatCallChannel") else { return }

    let channel = FlutterMethodChannel(name: "nexchat/call", binaryMessenger: registrar.messenger())
    callChannel = channel
    IncomingCallKit.shared.attach(channel: channel)
    VoipPushManager.shared.start(channel: channel)

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "proximity":
        let args = call.arguments as? [String: Any]
        UIDevice.current.isProximityMonitoringEnabled = (args?["enabled"] as? Bool) == true
        result(nil)
      case "stop":
        UIDevice.current.isProximityMonitoringEnabled = false
        IncomingCallKit.shared.dismissIncoming(clearStore: true)
        result(nil)
      case "start":
        result(nil)
      case "showIncoming":
        let args = call.arguments as? [String: Any] ?? [:]
        IncomingCallKit.shared.showIncoming(
          conversationId: args["conversationId"] as? String,
          sessionId: args["sessionId"] as? String,
          voiceOnly: (args["voiceOnly"] as? Bool) == true,
          callerName: (args["callerName"] as? String) ?? "NexChat",
          callerAvatar: args["callerAvatar"] as? String
        )
        result(nil)
      case "dismissIncoming":
        IncomingCallKit.shared.dismissIncoming(clearStore: true)
        result(nil)
      case "setForeground":
        let args = call.arguments as? [String: Any]
        IncomingCallKit.shared.setForeground((args?["value"] as? Bool) == true)
        result(nil)
      case "ready":
        IncomingCallKit.shared.markReady()
        result(nil)
      case "consumePending":
        result(IncomingCallKit.shared.consumePending())
      case "isEmulator", "clearLockScreen":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
      _ = self
    }

    let secure = FlutterMethodChannel(name: "nexchat/secure", binaryMessenger: registrar.messenger())
    self.secureChannel = secure
    secure.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setSecure":
        let args = call.arguments as? [String: Any]
        let enabled = (args?["enabled"] as? Bool) == true
        DispatchQueue.main.async {
          self?.setSecure(enabled)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// iOS cannot fully block screenshots like Android FLAG_SECURE.
  /// We black out the UI while screen recording / mirroring is active,
  /// and notify Flutter when a screenshot is taken during secure mode.
  private func setSecure(_ enabled: Bool) {
    secureEnabled = enabled
    if enabled {
      if captureObserver == nil {
        captureObserver = NotificationCenter.default.addObserver(
          forName: UIScreen.capturedDidChangeNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          self?.updateCaptureOverlay()
        }
      }
      if screenshotObserver == nil {
        screenshotObserver = NotificationCenter.default.addObserver(
          forName: UIApplication.userDidTakeScreenshotNotification,
          object: nil,
          queue: .main
        ) { [weak self] _ in
          guard self?.secureEnabled == true else { return }
          self?.secureChannel?.invokeMethod("onScreenshot", arguments: nil)
        }
      }
      updateCaptureOverlay()
    } else {
      if let obs = captureObserver {
        NotificationCenter.default.removeObserver(obs)
        captureObserver = nil
      }
      if let obs = screenshotObserver {
        NotificationCenter.default.removeObserver(obs)
        screenshotObserver = nil
      }
      hideCaptureOverlay()
    }
  }

  private func updateCaptureOverlay() {
    guard secureEnabled else {
      hideCaptureOverlay()
      return
    }
    if UIScreen.main.isCaptured {
      showCaptureOverlay()
    } else {
      hideCaptureOverlay()
    }
  }

  private func showCaptureOverlay() {
    guard secureOverlay == nil else { return }
    guard let window = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first else { return }
    let overlay = UIView(frame: window.bounds)
    overlay.backgroundColor = .black
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.isUserInteractionEnabled = true
    let label = UILabel()
    label.text = "تسجيل الشاشة غير مسموح"
    label.textColor = .white
    label.textAlignment = .center
    label.font = UIFont.boldSystemFont(ofSize: 16)
    label.translatesAutoresizingMaskIntoConstraints = false
    overlay.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
      label.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -24),
    ])
    window.addSubview(overlay)
    secureOverlay = overlay
  }

  private func hideCaptureOverlay() {
    secureOverlay?.removeFromSuperview()
    secureOverlay = nil
  }
}
