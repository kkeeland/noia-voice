// ThinkingIndicator.swift — Audio cues for acknowledgment and "still thinking"
// Noia Voice © 2025

import AVFoundation

final class ThinkingIndicator {
    
    enum Tone {
        case acknowledged    // Short beep: "I heard you"
        case thinking        // Periodic gentle tone: "still working"
        case ready           // Ascending tone: "response ready"
    }
    
    private var thinkingTimer: Timer?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let enabled: () -> Bool
    
    init(enabled: @escaping () -> Bool = { true }) {
        self.enabled = enabled
    }
    
    // MARK: - Control
    
    func playAcknowledged() {
        guard enabled() else { return }
        playTone(.acknowledged)
    }
    
    func startThinkingCues() {
        guard enabled() else { return }
        
        // Play first cue after 3 seconds, then every 4 seconds
        thinkingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.playTone(.thinking)
            self?.thinkingTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
                self?.playTone(.thinking)
            }
        }
    }
    
    func stopThinking() {
        thinkingTimer?.invalidate()
        thinkingTimer = nil
        stopAudioEngine()
    }
    
    func playReady() {
        guard enabled() else { return }
        playTone(.ready)
    }
    
    // MARK: - Tone Generation
    
    private func playTone(_ tone: Tone) {
        let sampleRate: Double = 44100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        
        let (frequency, duration, volume): (Double, Double, Float) = {
            switch tone {
            case .acknowledged:
                return (880.0, 0.08, 0.15)     // Short high beep
            case .thinking:
                return (440.0, 0.12, 0.08)     // Gentle low tone
            case .ready:
                return (660.0, 0.1, 0.12)      // Medium ascending
            }
        }()
        
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            var sample = Float(sin(2.0 * .pi * frequency * t))
            
            // For "ready" tone, add ascending sweep
            if tone == .ready {
                let sweepFreq = frequency + (frequency * 0.5 * t / duration)
                sample = Float(sin(2.0 * .pi * sweepFreq * t))
            }
            
            // Apply envelope (fade in/out) to avoid clicks
            let envelope: Float
            let fadeFrames = Int(sampleRate * 0.01) // 10ms fade
            if i < fadeFrames {
                envelope = Float(i) / Float(fadeFrames)
            } else if i > Int(frameCount) - fadeFrames {
                envelope = Float(Int(frameCount) - i) / Float(fadeFrames)
            } else {
                envelope = 1.0
            }
            
            channelData[i] = sample * volume * envelope
        }
        
        playBuffer(buffer, format: format)
    }
    
    private func playBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        do {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            
            try engine.start()
            player.play()
            player.scheduleBuffer(buffer) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    engine.stop()
                }
            }
            
            // Keep reference alive until playback completes
            self.audioEngine = engine
            self.playerNode = player
            
        } catch {
            print("[Tone] Playback error: \(error.localizedDescription)")
        }
    }
    
    private func stopAudioEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
    }
    
    deinit {
        stopThinking()
    }
}
