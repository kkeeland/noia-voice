// VoiceActivityDetector.swift — Energy-based VAD with auto-calibration
// Noia Voice © 2025

import AVFoundation
import Combine

final class VoiceActivityDetector: ObservableObject {
    
    // MARK: - Configuration
    
    var energyThreshold: Float = -40.0  // dB, will be calibrated
    var minSpeechFrames: Int = 5        // ~320ms at 1024/16kHz
    var silenceFramesForEnd: Int = 24   // ~1.5s silence = end of utterance
    
    // MARK: - State
    
    @Published private(set) var currentState: VADState = .silence
    @Published private(set) var currentEnergyDB: Float = -100.0
    @Published private(set) var isCalibrated = false
    
    private var speechFrameCount = 0
    private var silenceFrameCount = 0
    private var isInUtterance = false
    
    // Calibration
    private var calibrationSamples: [Float] = []
    private var calibrationFrameCount = 0
    private let calibrationFrames = 47  // ~3 seconds at 1024/16kHz
    private var calibrationComplete = false
    
    // Publishers
    let stateChanged = PassthroughSubject<VADState, Never>()
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    
    init() {}
    
    func configure(sensitivity: Double, silenceThreshold: Double) {
        // Map sensitivity 0.0-1.0 to energy threshold -25dB to -55dB
        self.energyThreshold = Float(-25.0 - (sensitivity * 30.0))
        self.minSpeechFrames = max(2, Int(8.0 - sensitivity * 6.0))
        
        // Map silence threshold in seconds to frame count
        // Assuming ~64ms per frame (1024 samples at 16kHz)
        self.silenceFramesForEnd = max(8, Int(silenceThreshold / 0.064))
    }
    
    // MARK: - Audio Processing
    
    func processBuffer(_ buffer: AVAudioPCMBuffer) {
        let energy = calculateRMSdB(buffer)
        
        DispatchQueue.main.async {
            self.currentEnergyDB = energy
        }
        
        // Auto-calibration on first N frames
        if !calibrationComplete {
            calibrate(energy: energy)
            return
        }
        
        // VAD logic
        let newState = evaluateFrame(energy: energy)
        
        if newState != currentState {
            DispatchQueue.main.async {
                self.currentState = newState
            }
            stateChanged.send(newState)
        }
    }
    
    // MARK: - Calibration
    
    private func calibrate(energy: Float) {
        calibrationSamples.append(energy)
        calibrationFrameCount += 1
        
        if calibrationFrameCount >= calibrationFrames {
            // Calculate noise floor from calibration period
            let sorted = calibrationSamples.sorted()
            let medianEnergy = sorted[sorted.count / 2]
            
            // Set threshold 10dB above noise floor, but respect configured sensitivity
            let calibratedThreshold = medianEnergy + 10.0
            
            // Use the more sensitive (lower) of configured vs calibrated
            if calibratedThreshold < energyThreshold {
                energyThreshold = calibratedThreshold
            }
            
            calibrationComplete = true
            DispatchQueue.main.async {
                self.isCalibrated = true
            }
            
            print("[VAD] Calibrated — noise floor: \(medianEnergy) dB, threshold: \(energyThreshold) dB")
        }
    }
    
    func resetCalibration() {
        calibrationSamples.removeAll()
        calibrationFrameCount = 0
        calibrationComplete = false
        isCalibrated = false
        speechFrameCount = 0
        silenceFrameCount = 0
        isInUtterance = false
        currentState = .silence
    }
    
    // MARK: - Frame Evaluation
    
    private func evaluateFrame(energy: Float) -> VADState {
        if energy > energyThreshold {
            speechFrameCount += 1
            silenceFrameCount = 0
            
            if speechFrameCount >= minSpeechFrames {
                isInUtterance = true
                return .speaking
            }
            
            // Not enough consecutive speech frames yet
            return isInUtterance ? .speaking : .silence
        } else {
            // Below threshold — silence
            if isInUtterance {
                silenceFrameCount += 1
                
                if silenceFrameCount >= silenceFramesForEnd {
                    // End of utterance
                    speechFrameCount = 0
                    silenceFrameCount = 0
                    isInUtterance = false
                    return .endOfUtterance
                }
                
                // Still in utterance, just a brief pause
                return .speaking
            } else {
                speechFrameCount = 0
                return .silence
            }
        }
    }
    
    // MARK: - Energy Calculation
    
    private func calculateRMSdB(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return -100.0 }
        
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return -100.0 }
        
        let samples = channelData[0]
        var sumOfSquares: Float = 0.0
        
        for i in 0..<frames {
            let sample = samples[i]
            sumOfSquares += sample * sample
        }
        
        let rms = sqrt(sumOfSquares / Float(frames))
        
        // Convert to dB, floor at -100
        if rms > 0 {
            return max(-100.0, 20.0 * log10(rms))
        }
        return -100.0
    }
}
