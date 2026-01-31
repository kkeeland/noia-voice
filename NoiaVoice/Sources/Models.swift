// Models.swift — Data models for Noia Voice
// Noia Voice © 2025

import Foundation

// MARK: - Gateway Messages

struct GatewayOutboundMessage: Codable {
    let type: String
    let content: String
    let sessionKey: String
    let metadata: MessageMetadata?
    
    struct MessageMetadata: Codable {
        let source: String
        let inputMethod: String
    }
    
    static func chat(_ text: String, sessionKey: String = "voice-iphone") -> GatewayOutboundMessage {
        GatewayOutboundMessage(
            type: "chat.message",
            content: text,
            sessionKey: sessionKey,
            metadata: MessageMetadata(source: "noia-voice", inputMethod: "speech")
        )
    }
}

struct GatewayInboundMessage: Codable {
    let type: String
    let content: String?
    let sessionKey: String?
    let error: String?
    
    var messageType: InboundType {
        InboundType(rawValue: type) ?? .unknown
    }
    
    enum InboundType: String {
        case responseStart = "chat.response.start"
        case responseChunk = "chat.response.chunk"
        case responseEnd = "chat.response.end"
        case error = "error"
        case pong = "pong"
        case unknown
    }
}

// MARK: - VAD State

enum VADState: Equatable {
    case silence
    case speaking
    case endOfUtterance
}

// MARK: - App State

enum VoiceAppState: Equatable {
    case idle
    case listening
    case processing
    case thinking
    case speaking
    case paused
    case error(String)
    
    var displayIcon: String {
        switch self {
        case .idle: return "mic.slash"
        case .listening: return "mic.fill"
        case .processing: return "waveform"
        case .thinking: return "brain"
        case .speaking: return "speaker.wave.3.fill"
        case .paused: return "pause.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    var displayEmoji: String {
        switch self {
        case .idle: return "⏸️"
        case .listening: return "🎙️"
        case .processing: return "📝"
        case .thinking: return "⏳"
        case .speaking: return "🔊"
        case .paused: return "⏸️"
        case .error: return "⚠️"
        }
    }
    
    var displayLabel: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .processing: return "Processing..."
        case .thinking: return "Thinking..."
        case .speaking: return "Speaking..."
        case .paused: return "Paused"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    
    var statusColor: String {
        switch self {
        case .idle: return "gray"
        case .listening: return "green"
        case .processing: return "blue"
        case .thinking: return "orange"
        case .speaking: return "purple"
        case .paused: return "yellow"
        case .error: return "red"
        }
    }
}

enum ActivationMode: String, CaseIterable, Codable {
    case vad = "VAD (Continuous)"
    case pushToTalk = "Push to Talk"
}

// MARK: - Connection State

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    
    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .reconnecting(let attempt): return "Reconnecting (\(attempt))..."
        }
    }
    
    var color: String {
        switch self {
        case .disconnected: return "red"
        case .connecting, .reconnecting: return "orange"
        case .connected: return "green"
        }
    }
}

// MARK: - Conversation

struct ConversationTurn: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let role: Role
    let content: String
    
    enum Role: String, Codable {
        case user
        case assistant
    }
    
    init(role: Role, content: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.role = role
        self.content = content
    }
}

// MARK: - ElevenLabs

struct ElevenLabsTTSRequest: Codable {
    let text: String
    let modelId: String
    let voiceSettings: VoiceSettings
    
    enum CodingKeys: String, CodingKey {
        case text
        case modelId = "model_id"
        case voiceSettings = "voice_settings"
    }
    
    struct VoiceSettings: Codable {
        let stability: Double
        let similarityBoost: Double
        
        enum CodingKeys: String, CodingKey {
            case stability
            case similarityBoost = "similarity_boost"
        }
    }
    
    static func make(text: String, stability: Double = 0.5, similarity: Double = 0.8) -> ElevenLabsTTSRequest {
        ElevenLabsTTSRequest(
            text: text,
            modelId: "eleven_turbo_v2_5",
            voiceSettings: VoiceSettings(stability: stability, similarityBoost: similarity)
        )
    }
}
