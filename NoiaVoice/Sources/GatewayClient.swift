// GatewayClient.swift — WebSocket client for Clawdbot gateway (v2 protocol)
// Noia Voice © 2025

import Foundation
import Combine

final class GatewayClient: ObservableObject {
    
    @Published private(set) var connectionState: ConnectionState = .disconnected
    
    /// Fires for each response text delta
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
    
    // Protocol state
    private var pendingRequests: [String: PendingRequest] = [:]
    private var currentRunId: String?
    private var accumulatedResponse = ""
    private var isHandshakeComplete = false
    private var requestCounter = 0
    
    private let settings: AppSettings
    
    struct PendingRequest {
        let method: String
        let completion: ((Bool, Any?, String?) -> Void)?
    }
    
    init(settings: AppSettings = .shared) {
        self.settings = settings
    }
    
    // MARK: - Connection
    
    func connect() {
        guard let url = settings.gatewayWSURL else {
            errorOccurred.send("Invalid gateway URL")
            return
        }
        
        shouldReconnect = true
        isHandshakeComplete = false
        
        DispatchQueue.main.async {
            self.connectionState = .connecting
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        // Configure session with custom delegate for TLS (tailnet self-signed)
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        
        let delegate = WebSocketDelegate()
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()
        
        // Start listening for messages
        listenForMessages()
        
        // Send connect handshake
        sendConnectHandshake()
        
        print("[GW] Connecting to \(url)")
    }
    
    func disconnect() {
        shouldReconnect = false
        isHandshakeComplete = false
        pingTimer?.invalidate()
        pingTimer = nil
        
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        pendingRequests.removeAll()
        currentRunId = nil
        
        DispatchQueue.main.async {
            self.connectionState = .disconnected
        }
    }
    
    // MARK: - Connect Handshake
    
    private func sendConnectHandshake() {
        let token = KeychainHelper.read(.gatewayToken) ?? ""
        
        let connectFrame: [String: Any] = [
            "type": "req",
            "id": nextRequestId(),
            "method": "connect",
            "params": [
                "minProtocol": 1,
                "maxProtocol": 1,
                "client": [
                    "id": "noia-voice-ios",
                    "displayName": "Noia Voice",
                    "version": "1.0.0",
                    "platform": "ios",
                    "deviceFamily": "iPhone",
                    "mode": "chat"
                ] as [String: Any],
                "auth": [
                    "token": token
                ]
            ] as [String: Any]
        ]
        
        sendJSON(connectFrame)
    }
    
    // MARK: - Send Chat Message
    
    func sendChatMessage(_ text: String) {
        guard isHandshakeComplete else {
            print("[GW] Cannot send — handshake not complete")
            errorOccurred.send("Not connected to gateway")
            return
        }
        
        let reqId = nextRequestId()
        let idempotencyKey = UUID().uuidString
        
        let frame: [String: Any] = [
            "type": "req",
            "id": reqId,
            "method": "chat.send",
            "params": [
                "sessionKey": settings.sessionKey ?? "voice-iphone",
                "message": text,
                "idempotencyKey": idempotencyKey
            ] as [String: Any]
        ]
        
        pendingRequests[reqId] = PendingRequest(method: "chat.send", completion: nil)
        accumulatedResponse = ""
        currentRunId = nil
        
        sendJSON(frame)
        print("[GW] Sent chat.send: \(text.prefix(50))")
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
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            print("[GW] Failed to decode: \(json.prefix(200))")
            return
        }
        
        switch type {
        case "hello-ok":
            handleHelloOk(obj)
            
        case "res":
            handleResponse(obj)
            
        case "event":
            handleEvent(obj)
            
        default:
            print("[GW] Unknown frame type: \(type)")
        }
    }
    
    // MARK: - Frame Handlers
    
    private func handleHelloOk(_ obj: [String: Any]) {
        isHandshakeComplete = true
        reconnectAttempt = 0
        
        DispatchQueue.main.async {
            self.connectionState = .connected
        }
        
        // Start ping timer
        startPingTimer()
        
        if let server = obj["server"] as? [String: Any],
           let version = server["version"] as? String {
            print("[GW] Connected — server v\(version)")
        } else {
            print("[GW] Connected (hello-ok)")
        }
    }
    
    private func handleResponse(_ obj: [String: Any]) {
        guard let id = obj["id"] as? String else { return }
        
        let ok = obj["ok"] as? Bool ?? false
        
        if let pending = pendingRequests.removeValue(forKey: id) {
            if !ok {
                let error = obj["error"] as? [String: Any]
                let message = error?["message"] as? String ?? "Request failed"
                print("[GW] \(pending.method) error: \(message)")
                
                if pending.method == "chat.send" {
                    errorOccurred.send(message)
                }
            } else {
                // chat.send accepted — response will come via events
                if pending.method == "chat.send" {
                    if let payload = obj["payload"] as? [String: Any],
                       let runId = payload["runId"] as? String {
                        currentRunId = runId
                    }
                }
            }
            
            pending.completion?(ok, obj["payload"], ok ? nil : "failed")
        }
    }
    
    private func handleEvent(_ obj: [String: Any]) {
        guard let event = obj["event"] as? String else { return }
        
        switch event {
        case "chat":
            handleChatEvent(obj["payload"] as? [String: Any] ?? [:])
            
        case "tick":
            // Heartbeat from server — connection is alive
            break
            
        case "snapshot":
            // State snapshot — ignore for voice
            break
            
        default:
            print("[GW] Unhandled event: \(event)")
        }
    }
    
    private func handleChatEvent(_ payload: [String: Any]) {
        guard let state = payload["state"] as? String else { return }
        
        switch state {
        case "delta":
            // Extract text content from the message
            if let message = payload["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let blockType = block["type"] as? String, blockType == "text",
                       let text = block["text"] as? String {
                        // First delta means response started
                        if accumulatedResponse.isEmpty {
                            responseStarted.send()
                        }
                        accumulatedResponse += text
                        responseChunk.send(text)
                    }
                }
            }
            
        case "final":
            // Extract final text
            var finalText = accumulatedResponse
            if let message = payload["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                var fullText = ""
                for block in content {
                    if let blockType = block["type"] as? String, blockType == "text",
                       let text = block["text"] as? String {
                        fullText += text
                    }
                }
                if !fullText.isEmpty {
                    finalText = fullText
                }
            }
            
            responseComplete.send(finalText)
            accumulatedResponse = ""
            currentRunId = nil
            
        case "error":
            let errorMsg = payload["errorMessage"] as? String ?? "Unknown error"
            errorOccurred.send(errorMsg)
            accumulatedResponse = ""
            currentRunId = nil
            
        case "aborted":
            accumulatedResponse = ""
            currentRunId = nil
            
        default:
            print("[GW] Unknown chat state: \(state)")
        }
    }
    
    // MARK: - Helpers
    
    private func nextRequestId() -> String {
        requestCounter += 1
        return "nv-\(requestCounter)"
    }
    
    private func sendJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else {
            print("[GW] Failed to serialize frame")
            return
        }
        
        webSocket?.send(.string(text)) { [weak self] error in
            if let error = error {
                print("[GW] Send error: \(error.localizedDescription)")
                self?.handleDisconnect()
            }
        }
    }
    
    // MARK: - Heartbeat
    
    private func startPingTimer() {
        DispatchQueue.main.async {
            self.pingTimer?.invalidate()
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.sendPing()
            }
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
        
        isHandshakeComplete = false
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
            self.session?.invalidateAndCancel()
            self.session = nil
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
        print("[GW] WebSocket transport opened")
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
