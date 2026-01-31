// AppSettings.swift — UserDefaults wrapper for app settings
// Noia Voice © 2025

import SwiftUI

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    // MARK: - Gateway
    
    @AppStorage("gatewayHost") var gatewayHost: String = "noia-main"
    @AppStorage("gatewayPort") var gatewayPort: Int = 18789
    @AppStorage("sessionKey") var sessionKey: String = "voice-iphone"
    
    var gatewayWSURL: URL? {
        URL(string: "wss://\(gatewayHost):\(gatewayPort)/ws")
    }
    
    // MARK: - Voice / TTS
    
    @AppStorage("ttsVoiceId") var ttsVoiceId: String = "pNInz6obpgDQGcFmaJgB"
    @AppStorage("ttsSpeed") var ttsSpeed: Double = 1.0
    @AppStorage("ttsStability") var ttsStability: Double = 0.5
    @AppStorage("ttsSimilarity") var ttsSimilarity: Double = 0.8
    @AppStorage("autoPlayTTS") var autoPlayTTS: Bool = true
    
    // MARK: - Activation
    
    @AppStorage("activationMode") var activationModeRaw: String = ActivationMode.vad.rawValue
    
    var activationMode: ActivationMode {
        get { ActivationMode(rawValue: activationModeRaw) ?? .vad }
        set { activationModeRaw = newValue.rawValue }
    }
    
    @AppStorage("autoActivateOnBluetooth") var autoActivateOnBluetooth: Bool = true
    @AppStorage("vadSensitivity") var vadSensitivity: Double = 0.5
    @AppStorage("silenceThreshold") var silenceThreshold: Double = 1.5
    
    // MARK: - Audio Cues
    
    @AppStorage("enableAcknowledgedBeep") var enableAcknowledgedBeep: Bool = true
    @AppStorage("enableThinkingCue") var enableThinkingCue: Bool = true
    
    // MARK: - UI
    
    @AppStorage("autoDimSeconds") var autoDimSeconds: Double = 10.0
    @AppStorage("keepScreenOn") var keepScreenOn: Bool = true
    
    // MARK: - Computed
    
    var hasGatewayToken: Bool {
        KeychainHelper.exists(.gatewayToken)
    }
    
    var hasElevenLabsKey: Bool {
        KeychainHelper.exists(.elevenLabsKey)
    }
    
    var isConfigured: Bool {
        hasGatewayToken && hasElevenLabsKey
    }
    
    // MARK: - VAD Computed Thresholds
    
    /// Energy threshold in dB, mapped from 0.0-1.0 sensitivity
    var vadEnergyThreshold: Float {
        // sensitivity 0.0 = -25 dB (less sensitive), 1.0 = -55 dB (very sensitive)
        Float(-25.0 - (vadSensitivity * 30.0))
    }
    
    /// Minimum speech frames before triggering (lower = more responsive)
    var vadMinSpeechFrames: Int {
        max(2, Int(8.0 - vadSensitivity * 6.0))
    }
}
