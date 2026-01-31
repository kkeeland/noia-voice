// SpeechRecognizer.swift — Apple Speech framework, on-device only
// Noia Voice © 2025

import Speech
import AVFoundation
import Combine

final class SpeechRecognizer: ObservableObject {
    
    private let speechRecognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @Published private(set) var partialTranscript: String = ""
    @Published private(set) var isRecognizing = false
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    
    /// Fires when a final transcript is ready
    let finalTranscript = PassthroughSubject<String, Never>()
    
    /// Fires with partial updates
    let partialUpdate = PassthroughSubject<String, Never>()
    
    // Contextual strings to improve recognition of custom vocabulary
    private let contextualStrings = [
        "Noia", "Clawdbot", "Adaptaphoria", "HelloSpore", "Bagtek",
        "Kevin", "Tailnet", "gateway"
    ]
    
    init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                }
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    // MARK: - Recognition Control
    
    func startRecognition() throws {
        // Cancel any existing task
        stopRecognition()
        
        guard speechRecognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = contextualStrings
        
        // Disable punctuation for cleaner voice-to-text
        if #available(iOS 17.0, *) {
            request.addsPunctuation = true
        }
        
        self.recognitionRequest = request
        
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                
                DispatchQueue.main.async {
                    self.partialTranscript = text
                }
                
                if result.isFinal {
                    self.finalTranscript.send(text)
                    DispatchQueue.main.async {
                        self.isRecognizing = false
                    }
                } else {
                    self.partialUpdate.send(text)
                }
            }
            
            if let error = error {
                // Don't treat cancellation as an error
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    // Request was cancelled — expected during stopRecognition
                    return
                }
                
                print("[STT] Recognition error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isRecognizing = false
                }
            }
        }
        
        DispatchQueue.main.async {
            self.isRecognizing = true
            self.partialTranscript = ""
        }
    }
    
    /// Feed audio buffer to the recognition request
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }
    
    /// End the current recognition request and get final result
    func finishRecognition() {
        recognitionRequest?.endAudio()
        // Task will fire final result via the completion handler
    }
    
    /// Cancel without waiting for final result
    func stopRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        DispatchQueue.main.async {
            self.isRecognizing = false
        }
    }
    
    // MARK: - Restart (Apple limits on-device to ~1 minute)
    
    /// Restart recognition for a new utterance
    func restartForNewUtterance() throws {
        stopRecognition()
        try startRecognition()
    }
}

// MARK: - Errors

enum SpeechError: LocalizedError {
    case recognizerUnavailable
    case notAuthorized
    
    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognizer is unavailable"
        case .notAuthorized: return "Speech recognition not authorized"
        }
    }
}
