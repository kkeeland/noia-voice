// TTSEngine.swift — ElevenLabs streaming TTS with Bluetooth A2DP output
// Noia Voice © 2025

import AVFoundation
import Combine

final class TTSEngine: ObservableObject {
    
    @Published private(set) var isSpeaking = false
    @Published private(set) var currentlySpeaking: String = ""
    
    /// Fires when all queued speech is done
    let didFinishSpeaking = PassthroughSubject<Void, Never>()
    
    private var audioPlayer: AVAudioPlayer?
    private var speechQueue: [String] = []
    private var isProcessingQueue = false
    private let settings: AppSettings
    
    private var currentTask: URLSessionDataTask?
    
    init(settings: AppSettings = .shared) {
        self.settings = settings
    }
    
    // MARK: - Public API
    
    /// Queue a sentence for TTS playback
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        speechQueue.append(trimmed)
        processQueue()
    }
    
    /// Queue multiple sentences extracted from a response
    func speakSentences(_ sentences: [String]) {
        for sentence in sentences {
            speak(sentence)
        }
    }
    
    /// Stop all speech immediately (e.g., user interrupts)
    func stop() {
        currentTask?.cancel()
        currentTask = nil
        
        audioPlayer?.stop()
        audioPlayer = nil
        
        speechQueue.removeAll()
        isProcessingQueue = false
        
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.currentlySpeaking = ""
        }
    }
    
    // MARK: - Queue Processing
    
    private func processQueue() {
        guard !isProcessingQueue, !speechQueue.isEmpty else { return }
        
        isProcessingQueue = true
        let text = speechQueue.removeFirst()
        
        DispatchQueue.main.async {
            self.isSpeaking = true
            self.currentlySpeaking = text
        }
        
        fetchAndPlay(text: text) { [weak self] in
            guard let self = self else { return }
            self.isProcessingQueue = false
            
            if self.speechQueue.isEmpty {
                DispatchQueue.main.async {
                    self.isSpeaking = false
                    self.currentlySpeaking = ""
                }
                self.didFinishSpeaking.send()
            } else {
                self.processQueue()
            }
        }
    }
    
    // MARK: - ElevenLabs API
    
    private func fetchAndPlay(text: String, completion: @escaping () -> Void) {
        guard let apiKey = KeychainHelper.read(.elevenLabsKey), !apiKey.isEmpty else {
            print("[TTS] No ElevenLabs API key configured")
            completion()
            return
        }
        
        let voiceId = settings.ttsVoiceId
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)/stream") else {
            print("[TTS] Invalid URL")
            completion()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        let body = ElevenLabsTTSRequest.make(
            text: text,
            stability: settings.ttsStability,
            similarity: settings.ttsSimilarity
        )
        
        guard let bodyData = try? JSONEncoder().encode(body) else {
            completion()
            return
        }
        
        request.httpBody = bodyData
        
        // Add output format query parameter
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "output_format", value: "mp3_22050_32")
        ]
        request.url = components.url
        
        currentTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { completion() }
            
            if let error = error {
                if (error as NSError).code == NSURLErrorCancelled { return }
                print("[TTS] Fetch error: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[TTS] Invalid response")
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
                print("[TTS] API error \(httpResponse.statusCode): \(body.prefix(200))")
                return
            }
            
            guard let audioData = data, !audioData.isEmpty else {
                print("[TTS] Empty audio data")
                return
            }
            
            self?.playAudioData(audioData)
        }
        
        currentTask?.resume()
    }
    
    // MARK: - Audio Playback
    
    private func playAudioData(_ data: Data) {
        do {
            // Ensure audio session is set for playback
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
            )
            
            let player = try AVAudioPlayer(data: data)
            player.delegate = playbackDelegate
            player.volume = 1.0
            
            // Adjust rate if speed != 1.0
            if settings.ttsSpeed != 1.0 {
                player.enableRate = true
                player.rate = Float(settings.ttsSpeed)
            }
            
            self.audioPlayer = player
            playbackDelegate.onFinish = { [weak self] in
                self?.audioPlayer = nil
            }
            
            player.prepareToPlay()
            player.play()
            
            // Block until playback completes (we're on a background thread)
            while player.isPlaying {
                Thread.sleep(forTimeInterval: 0.05)
            }
            
        } catch {
            print("[TTS] Playback error: \(error.localizedDescription)")
        }
    }
    
    private lazy var playbackDelegate = AudioPlayerDelegate()
    
    deinit {
        stop()
    }
}

// MARK: - Audio Player Delegate

private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("[TTS] Decode error: \(error?.localizedDescription ?? "unknown")")
        onFinish?()
    }
}

// MARK: - Sentence Extraction

extension TTSEngine {
    
    /// Extract complete sentences from accumulated text.
    /// Returns (sentences, remainingText)
    static func extractSentences(from text: String) -> (sentences: [String], remainder: String) {
        var sentences: [String] = []
        var remainder = text
        
        // Split on sentence-ending punctuation followed by a space or end of string
        let pattern = #"[^.!?]*[.!?](?:\s|$)"#
        
        while let range = remainder.range(of: pattern, options: .regularExpression) {
            let sentence = String(remainder[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            remainder = String(remainder[range.upperBound...])
        }
        
        return (sentences, remainder.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
