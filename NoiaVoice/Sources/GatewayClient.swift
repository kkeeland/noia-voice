// GatewayClient.swift — WebSocket client for Clawdbot gateway
// Noia Voice © 2025

import Foundation
import Combine

final class GatewayClient: ObservableObject {
    
    @Published private(set) var connectionState: ConnectionState = .disconnected
    
    /// Fires for each response chunk
    let responseChunk = PassthroughSubject<String, Never>()
    /// Fires when a full response is complete
    let responseComplete = PassthroughSubject<String, Never>()
    /// Fires when response starts streaming
    let responseStarted = PassthroughSubject<Void, Never>()
    /// Fires on errors
    let errorOccurred = PassthroughSubject<String, Never>()
    
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var reconnectAttempt = 0
    private let maxReconnectAttempt = 10
    private var shouldReconnect = true
    private var accumulatedResponse = ""
    
    private let settings: AppSettings
    
    init(settings: AppSettings = .shared) {
        self.settings = settings
    }
    
    // MARK: - Connection
    
    func connect() {
        guard let url = settings.gatewayWSURL else {
            errorOccurred.send("Invalid gateway URL")
            return
        }
        
        guard let token = KeychainHelper.read(.gatewayToken), !token.isEmpty else {
            errorOccurred.send("No gateway token configured")
            return
        }
        
        shouldReconnect = true
        
        DispatchQueue.main.async {
            self.connectionState = .connecting
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        
        // Configure session with custom delegate for TLS (tailnet self-signed)
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        
        let delegate = WebSocketDelegate()
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()
        
        // Start listening
        listenForMessages()
        
        // Start ping timer
        startPingTimer()
        
        DispatchQueue.main.async {
            self.connectionState = .connected
            self.reconnectAttempt = 0
        }
        
        print("[GW] Connected to \(url)")
    }
    
    func disconnect() {
        shouldReconnect = false
        pingTimer?.invalidate()
        pingTimer = nil
        
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        
        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }
    }
    
    // MARK: - Send Message
    
    func sendChatMessage(_ text: String) {
        let message = GatewayOutboundMessage.chat(text, sessionKey: settings.sessionKey)
        
        guard let data = try? JSONEncoder().encode(message) else {
            errorOccurred.send("Failed to encode message")
            return
        }
        
        webSocket?.send(.data(data)) { [weak self] error in
            if let error = error {
                print("[GW] Send error: \(error.localizedDescription)")
                self?.errorOccurred.send("Send failed: \(error.localizedDescription)")
                self?.handleDisconnect()
            }
        }
        
        accumulatedResponse = ""
    }
    
    // MARK: - Receive Messages
    
    private func listenForMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleInbound(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleInbound(text)
                    }
                @unknown default:
                    break
                }
                // Continue listening
                self.listenForMessages()
                
            case .failure(let error):
                print("[GW] Receive error: \(error.localizedDescription)")
                self.handleDisconnect()
            }
        }
    }
    
    private func handleInbound(_ json: String) {
        guard let data = json.data(using: .utf8),
              let msg = try? JSONDecoder().decode(GatewayInboundMessage.self, from: data) else {
            print("[GW] Failed to decode: \(json.prefix(200))")
            return
        }
        
        switch msg.messageType {
        case .responseStart:
            accumulatedResponse = ""
            responseStarted.send()
            
        case .responseChunk:
            if let chunk = msg.content {
                accumulatedResponse += chunk
                responseChunk.send(chunk)
            }
            
        case .responseEnd:
            let finalContent = msg.content ?? accumulatedResponse
            responseComplete.send(finalContent)
            accumulatedResponse = ""
            
        case .error:
            errorOccurred.send(msg.error ?? msg.content ?? "Unknown gateway error")
            
        case .pong:
            break // Heartbeat acknowledged
            
        case .unknown:
            print("[GW] Unknown message type: \(msg.type)")
        }
    }
    
    // MARK: - Heartbeat
    
    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func sendPing() {
        webSocket?.sendPing { [weak self] error in
            if let error = error {
                print("[GW] Ping failed: \(error.localizedDescription)")
                self?.handleDisconnect()
            }
        }
    }
    
    // MARK: - Reconnection
    
    private func handleDisconnect() {
        guard shouldReconnect else { return }
        
        reconnectAttempt += 1
        
        if reconnectAttempt > maxReconnectAttempt {
            DispatchQueue.main.async {
                self.connectionState = .disconnected
            }
            errorOccurred.send("Max reconnection attempts reached")
            return
        }
        
        DispatchQueue.main.async {
            self.connectionState = .reconnecting(attempt: self.reconnectAttempt)
        }
        
        // Exponential backoff: 1s, 2s, 4s, 8s, ... max 30s
        let delay = min(30.0, pow(2.0, Double(reconnectAttempt - 1)))
        
        print("[GW] Reconnecting in \(delay)s (attempt \(reconnectAttempt))")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.shouldReconnect else { return }
            self.webSocket?.cancel(with: .goingAway, reason: nil)
            self.webSocket = nil
            self.connect()
        }
    }
    
    deinit {
        disconnect()
    }
}

// MARK: - WebSocket Delegate (TLS handling for tailnet)

private class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Trust tailnet certificates
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("[GW] WebSocket opened")
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("[GW] WebSocket closed: \(closeCode)")
    }
}
