// SettingsView.swift — Configuration for gateway, voice, activation, audio
// Noia Voice © 2025

import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var gatewayToken: String = ""
    @State private var elevenLabsKey: String = ""
    @State private var showGatewayToken = false
    @State private var showElevenLabsKey = false
    @State private var tokenSaved = false
    @State private var elevenLabsSaved = false
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Gateway Section
                Section {
                    HStack {
                        Text("Host")
                        Spacer()
                        TextField("noia-main", text: $settings.gatewayHost)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("18789", value: $settings.gatewayPort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                    
                    HStack {
                        Text("Session Key")
                        Spacer()
                        TextField("voice-iphone", text: $settings.sessionKey)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    
                    // Token field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Bearer Token")
                            Spacer()
                            if settings.hasGatewayToken {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                        
                        HStack {
                            if showGatewayToken {
                                TextField("Enter token", text: $gatewayToken)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("Enter token", text: $gatewayToken)
                                    .textInputAutocapitalization(.never)
                            }
                            
                            Button {
                                showGatewayToken.toggle()
                            } label: {
                                Image(systemName: showGatewayToken ? "eye.slash" : "eye")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        if !gatewayToken.isEmpty {
                            Button("Save Token") {
                                KeychainHelper.save(gatewayToken, for: .gatewayToken)
                                tokenSaved = true
                                gatewayToken = ""
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    tokenSaved = false
                                }
                            }
                            .foregroundColor(.blue)
                        }
                        
                        if tokenSaved {
                            Text("✅ Token saved to Keychain")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    if let url = settings.gatewayWSURL {
                        HStack {
                            Text("URL")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(url.absoluteString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("Gateway", systemImage: "network")
                }
                
                // MARK: - ElevenLabs Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("API Key")
                            Spacer()
                            if settings.hasElevenLabsKey {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                        
                        HStack {
                            if showElevenLabsKey {
                                TextField("Enter key", text: $elevenLabsKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("Enter key", text: $elevenLabsKey)
                                    .textInputAutocapitalization(.never)
                            }
                            
                            Button {
                                showElevenLabsKey.toggle()
                            } label: {
                                Image(systemName: showElevenLabsKey ? "eye.slash" : "eye")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        if !elevenLabsKey.isEmpty {
                            Button("Save Key") {
                                KeychainHelper.save(elevenLabsKey, for: .elevenLabsKey)
                                elevenLabsSaved = true
                                elevenLabsKey = ""
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    elevenLabsSaved = false
                                }
                            }
                            .foregroundColor(.blue)
                        }
                        
                        if elevenLabsSaved {
                            Text("✅ Key saved to Keychain")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    HStack {
                        Text("Voice ID")
                        Spacer()
                        TextField("Voice ID", text: $settings.ttsVoiceId)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Speed")
                            Spacer()
                            Text(String(format: "%.1fx", settings.ttsSpeed))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.ttsSpeed, in: 0.5...2.0, step: 0.1)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Stability")
                            Spacer()
                            Text(String(format: "%.0f%%", settings.ttsStability * 100))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.ttsStability, in: 0...1)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Similarity")
                            Spacer()
                            Text(String(format: "%.0f%%", settings.ttsSimilarity * 100))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.ttsSimilarity, in: 0...1)
                    }
                    
                    Toggle("Auto-play responses", isOn: $settings.autoPlayTTS)
                } header: {
                    Label("Voice (ElevenLabs)", systemImage: "speaker.wave.2")
                }
                
                // MARK: - Activation Section
                Section {
                    Picker("Mode", selection: $settings.activationModeRaw) {
                        ForEach(ActivationMode.allCases, id: \.rawValue) { mode in
                            Text(mode.rawValue).tag(mode.rawValue)
                        }
                    }
                    
                    Toggle("Auto-activate on Tesla BT", isOn: $settings.autoActivateOnBluetooth)
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("VAD Sensitivity")
                            Spacer()
                            Text(sensitivityLabel)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.vadSensitivity, in: 0...1)
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Silence Threshold")
                            Spacer()
                            Text(String(format: "%.1fs", settings.silenceThreshold))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.silenceThreshold, in: 0.5...3.0, step: 0.1)
                    }
                } header: {
                    Label("Activation", systemImage: "waveform")
                }
                
                // MARK: - Audio Cues Section
                Section {
                    Toggle("\"Acknowledged\" beep", isOn: $settings.enableAcknowledgedBeep)
                    Toggle("\"Thinking\" indicator", isOn: $settings.enableThinkingCue)
                } header: {
                    Label("Audio Cues", systemImage: "bell")
                }
                
                // MARK: - Display Section
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Auto-dim after")
                            Spacer()
                            Text(String(format: "%.0fs", settings.autoDimSeconds))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.autoDimSeconds, in: 5...60, step: 5)
                    }
                    
                    Toggle("Keep screen on", isOn: $settings.keepScreenOn)
                } header: {
                    Label("Display", systemImage: "sun.max")
                }
                
                // MARK: - Info
                Section {
                    HStack {
                        Text("Model")
                        Spacer()
                        Text("eleven_turbo_v2_5")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("STT")
                        Spacer()
                        Text("Apple Speech (on-device)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Info", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var sensitivityLabel: String {
        switch settings.vadSensitivity {
        case 0..<0.3: return "Low"
        case 0.3..<0.6: return "Medium"
        case 0.6..<0.8: return "High"
        default: return "Very High"
        }
    }
}

#Preview {
    SettingsView()
}
