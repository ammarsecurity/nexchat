import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NexChatCallChannel") else { return }
    // Background audio (UIBackgroundModes) keeps LiveKit alive on iOS, so only proximity needs native code.
    let channel = FlutterMethodChannel(name: "nexchat/call", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "proximity":
        let args = call.arguments as? [String: Any]
        UIDevice.current.isProximityMonitoringEnabled = (args?["enabled"] as? Bool) == true
        result(nil)
      case "stop":
        UIDevice.current.isProximityMonitoringEnabled = false
        result(nil)
      case "start":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
