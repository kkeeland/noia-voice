// ConversationManager.swift — Orchestrates VAD → STT → Gateway → TTS flow
// Noia Voice © 2025

import Foundation
import Combine
import AVFoundation

@MainActor
final class ConversationManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var appState: VoiceAppState = .idle
    @Published private(set) var currentTranscript: String = ""
    @Published private(set) var lastResponse: String = ""
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var isBluetoothConnected = false
    @Published private(set) var bluetoothDeviceName: String?
    @Published private(set) var isMuted = false
    @Published var conversationHistory: [ConversationTurn] = []
    
    // MARK: - Components
    
    let audioCapture = AudioCapture()
    let vad = VoiceActivityDetector()
    let speechRecognizer = SpeechRecognizer()
    let gateway = GatewayClient()
    let ttsEngine = TTSEngine()
    let bluetoothMonitor = BluetoothMonitor()
    let thinkingIndicator: ThinkingIndicator
    let settings = AppSettings.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var accumulatedText = ""
    private var lastSentenceBoundary = 0
    
    // MARK: - Init
    
    init() {
        self.thinkingIndicator = ThinkingIndicator(enabled: { [weak settings] in
            settings?.enableThinkingCue ?? true
        })
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Gateway connection state
        gateway.$connectionState
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionState)
        
        // Bluetooth state
        bluetoothMonitor.$isBluetoothConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isBluetoothConnected)
        
        bluetoothMonitor.$connectedDeviceName
            .receive(on: DispatchQueue.main)
            .assign(to: &$bluetoothDeviceName)
        
        // VAD state changes → control STT
        vad.stateChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleVADState(state)
            }
            .store(in: &cancellables)
        
        // Audio buffers → VAD + STT
        audioCapture.audioBufferSubject
            .sink { [weak self] buffer in
                guard let self = self, !self.isMuted else { return }
                self.vad.processBuffer(buffer)
                if self.speechRecognizer.isRecognizing {
                    self.speechRecognizer.appendBuffer(buffer)
                }
            }
            .store(in: &cancellables)
        
        // STT partial updates
        speechRecognizer.partialUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.currentTranscript = text
            }
            .store(in: &cancellables)
        
        // STT final transcript → send to gateway
        speechRecognizer.finalTranscript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.handleFinalTranscript(text)
            }
            .store(in: &cancellables)
        
        // Gateway response started
        gateway.responseStarted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.appState = .thinking
                self?.accumulatedText = ""
                self?.lastSentenceBoundary = 0
            }
            .store(in: &cancellables)
        
        // Gateway response chunks → accumulate and stream to TTS
        gateway.responseChunk
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chunk in
                self?.handleResponseChunk(chunk)
            }
            .store(in: &cancellables)
        
        // Gateway response complete
        gateway.responseComplete
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fullResponse in
                self?.handleResponseComplete(fullResponse)
            }
            .store(in: &cancellables)
        
        // Gateway errors
        gateway.errorOccurred
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.appState = .error(error)
                self?.thinkingIndicator.stopThinking()
            }
            .store(in: &cancellables)
        
        // TTS finished speaking
        ttsEngine.didFinishSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                if self.appState == .speaking {
                    self.resumeListening()
                }
            }
            .store(in: &cancellables)
        
        // Auto-activate on Tesla Bluetooth
        bluetoothMonitor.teslaConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self, self.settings.autoActivateOnBluetooth else { return }
                self.startSession()
            }
            .store(in: &cancellables)
        
        bluetoothMonitor.teslaDisconnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self, self.settings.autoActivateOnBluetooth else { return }
                self.pauseSession()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Session Control
    
    func startSession() {
        guard settings.isConfigured else {
            appState = .error("Configure gateway and ElevenLabs keys in Settings")
            return
        }
        
        Task {
            // Request permissions
            let sttAuthorized = await speechRecognizer.requestAuthorization()
            guard sttAuthorized else {
                appState = .error("Speech recognition not authorized")
                return
            }
            
            // Connect gateway
            gateway.connect()
            
            // Start Bluetooth monitoring
            bluetoothMonitor.startMonitoring()
            
            // Start listening
            do {
                try audioCapture.startCapture()
                vad.configure(
                    sensitivity: settings.vadSensitivity,
                    silenceThreshold: settings.silenceThreshold
                )
                appState = .listening
            } catch {
                appState = .error("Audio capture: \(error.localizedDescription)")
            }
        }
    }
    
    func stopSession() {
        audioCapture.stopCapture()
        speechRecognizer.stopRecognition()
        gateway.disconnect()
        ttsEngine.stop()
        thinkingIndicator.stopThinking()
        bluetoothMonitor.stopMonitoring()
        vad.resetCalibration()
        appState = .idle
    }
    
    func pauseSession() {
        audioCapture.stopCapture()
        speechRecognizer.stopRecognition()
        thinkingIndicator.stopThinking()
        appState = .paused
    }
    
    func resumeListening() {
        guard appState != .idle else { return }
        
        do {
            try audioCapture.startCapture()
            vad.resetCalibration()
            vad.configure(
                sensitivity: settings.vadSensitivity,
                silenceThreshold: settings.silenceThreshold
            )
            appState = .listening
            currentTranscript = ""
        } catch {
            appState = .error("Resume failed: \(error.localizedDescription)")
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            speechRecognizer.stopRecognition()
        }
    }
    
    // MARK: - Push-to-Talk
    
    func pushToTalkBegan() {
        guard settings.activationMode == .pushToTalk else { return }
        
        do {
            try audioCapture.startCapture()
            try speechRecognizer.startRecognition()
            appState = .listening
            currentTranscript = ""
        } catch {
            appState = .error(error.localizedDescription)
        }
    }
    
    func pushToTalkEnded() {
        guard settings.activationMode == .pushToTalk else { return }
        
        speechRecognizer.finishRecognition()
        appState = .processing
    }
    
    // MARK: - VAD Handling
    
    private func handleVADState(_ state: VADState) {
        guard settings.activationMode == .vad else { return }
        
        switch state {
        case .speaking:
            if !speechRecognizer.isRecognizing {
                do {
                    try speechRecognizer.startRecognition()
                    appState = .listening
                } catch {
                    print("[CM] STT start error: \(error)")
                }
            }
            
        case .endOfUtterance:
            if speechRecognizer.isRecognizing {
                speechRecognizer.finishRecognition()
                appState = .processing
            }
            
        case .silence:
            break
        }
    }
    
    // MARK: - Transcript Handling
    
    private func handleFinalTranscript(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resumeListening()
            return
        }
        
        currentTranscript = text
        
        // Save to history
        conversationHistory.append(ConversationTurn(role: .user, content: text))
        
        // Play acknowledged beep
        if settings.enableAcknowledgedBeep {
            thinkingIndicator.playAcknowledged()
        }
        
        // Send to gateway
        appState = .thinking
        gateway.sendChatMessage(text)
        
        // Start thinking cues
        if settings.enableThinkingCue {
            thinkingIndicator.startThinkingCues()
        }
    }
    
    // MARK: - Response Handling
    
    private func handleResponseChunk(_ chunk: String) {
        accumulatedText += chunk
        
        // Extract complete sentences for streaming TTS
        if settings.autoPlayTTS {
            let (sentences, remainder) = TTSEngine.extractSentences(from: accumulatedText)
            
            if !sentences.isEmpty {
                thinkingIndicator.stopThinking()
                appState = .speaking
                
                // Stop audio capture while speaking to prevent feedback
                audioCapture.stopCapture()
                speechRecognizer.stopRecognition()
                
                ttsEngine.speakSentences(sentences)
                accumulatedText = remainder
            }
        }
        
        // Update displayed response
        lastResponse = accumulatedText
    }
    
    private func handleResponseComplete(_ fullResponse: String) {
        thinkingIndicator.stopThinking()
        lastResponse = fullResponse
        
        // Save to history
        conversationHistory.append(ConversationTurn(role: .assistant, content: fullResponse))
        
        // Speak any remaining text that wasn't sentence-terminated
        if settings.autoPlayTTS {
            let remaining = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                appState = .speaking
                ttsEngine.speak(remaining)
            }
        }
        
        accumulatedText = ""
        lastSentenceBoundary = 0
        
        // If TTS is off or no audio to play, resume listening
        if !settings.autoPlayTTS || !ttsEngine.isSpeaking {
            resumeListening()
        }
    }
    
    // MARK: - Interrupt
    
    /// User started speaking while TTS is playing — interrupt
    func interruptSpeaking() {
        ttsEngine.stop()
        thinkingIndicator.stopThinking()
        accumulatedText = ""
        resumeListening()
    }
}
