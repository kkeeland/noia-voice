// AudioCapture.swift — AVAudioEngine mic capture with Bluetooth HFP routing
// Noia Voice © 2025

import AVFoundation
import Combine

final class AudioCapture: ObservableObject {
    
    private let engine = AVAudioEngine()
    private var isCapturing = false
    
    /// Published audio buffers for downstream consumers (VAD, STT)
    let audioBufferSubject = PassthroughSubject<AVAudioPCMBuffer, Never>()
    
    @Published var isRunning = false
    @Published var currentInputRoute: String = "Unknown"
    @Published var isBluetoothInput = false
    
    // MARK: - Audio Session Setup
    
    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [
                .allowBluetooth,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .mixWithOthers
            ]
        )
        
        // Prefer Bluetooth input if available
        if let bluetoothInput = session.availableInputs?.first(where: { input in
            input.portType == .bluetoothHFP || input.portType == .bluetoothLE
        }) {
            try session.setPreferredInput(bluetoothInput)
        }
        
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        
        updateRouteInfo()
        
        // Listen for route changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    // MARK: - Capture Control
    
    func startCapture() throws {
        guard !isCapturing else { return }
        
        try configureAudioSession()
        
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // Validate format
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.invalidFormat
        }
        
        // Install tap — 1024 frames for low-latency VAD
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.audioBufferSubject.send(buffer)
        }
        
        engine.prepare()
        try engine.start()
        
        isCapturing = true
        DispatchQueue.main.async {
            self.isRunning = true
        }
    }
    
    func stopCapture() {
        guard isCapturing else { return }
        
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        isCapturing = false
        DispatchQueue.main.async {
            self.isRunning = false
        }
    }
    
    // MARK: - Route Monitoring
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange:
            updateRouteInfo()
            
            // Restart engine if running to pick up new route
            if isCapturing {
                stopCapture()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    try? self?.startCapture()
                }
            }
        default:
            break
        }
    }
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // System interrupted audio (phone call, etc.)
            stopCapture()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    try? self?.startCapture()
                }
            }
        @unknown default:
            break
        }
    }
    
    private func updateRouteInfo() {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.currentRoute.inputs
        
        let isBT = inputs.contains { input in
            input.portType == .bluetoothHFP ||
            input.portType == .bluetoothLE ||
            input.portType == .bluetoothA2DP
        }
        
        let routeName = inputs.first?.portName ?? "Unknown"
        
        DispatchQueue.main.async {
            self.currentInputRoute = routeName
            self.isBluetoothInput = isBT
        }
    }
    
    /// Returns the current capture format for downstream use
    var captureFormat: AVAudioFormat? {
        guard isCapturing else { return nil }
        return engine.inputNode.outputFormat(forBus: 0)
    }
    
    deinit {
        stopCapture()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case invalidFormat
    case engineStartFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Invalid audio format from input device"
        case .engineStartFailed: return "Failed to start audio engine"
        }
    }
}
