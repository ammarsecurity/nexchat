import Foundation
import AVFoundation
import Capacitor

/// توجيه الصوت بين مكبّر الصوت وسماعة الأذن أثناء مكالمات WebRTC/LiveKit (مطابق لـ SpeakerAudioPlugin على Android).
/// يستخدم AVAudioSession: voiceChat + overrideOutputAudioPort — ضروري لأن setSinkId وحده لا يكفي في WKWebView.
@objc(SpeakerAudioPlugin)
public class SpeakerAudioPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SpeakerAudioPlugin"
    public let jsName = "SpeakerAudio"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setSpeakerOn", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resetAudioMode", returnType: CAPPluginReturnPromise)
    ]

    @objc func setSpeakerOn(_ call: CAPPluginCall) {
        let speaker = call.getBool("speaker", false)
        DispatchQueue.main.async {
            do {
                let session = AVAudioSession.sharedInstance()
                // voiceChat: أولوية سماعة الأذن عند عدم فرض السبيكر؛ بدون defaultToSpeaker
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
                try session.setActive(true)
                if speaker {
                    try session.overrideOutputAudioPort(.speaker)
                } else {
                    try session.overrideOutputAudioPort(.none)
                }
                call.resolve(["ok": true])
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func resetAudioMode(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.overrideOutputAudioPort(.none)
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                try? session.setActive(false)
            }
            call.resolve()
        }
    }
}
