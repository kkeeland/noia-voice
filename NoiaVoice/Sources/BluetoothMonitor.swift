// BluetoothMonitor.swift — Detects Tesla Bluetooth, auto-activates voice mode
// Noia Voice © 2025

import AVFoundation
import Combine

final class BluetoothMonitor: ObservableObject {
    
    @Published private(set) var isBluetoothConnected = false
    @Published private(set) var isTeslaConnected = false
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var bluetoothPortType: String = ""
    
    /// Fires when Tesla BT connects
    let teslaConnected = PassthroughSubject<Void, Never>()
    /// Fires when Tesla BT disconnects
    let teslaDisconnected = PassthroughSubject<Void, Never>()
    
    // Names that indicate Tesla car Bluetooth
    private let teslaIdentifiers = [
        "Tesla", "Model 3", "Model Y", "Model S", "Model X", "Cybertruck"
    ]
    
    init() {}
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        // Check current state immediately
        checkCurrentRoute()
        
        // Listen for route changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    func stopMonitoring() {
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    // MARK: - Route Checking
    
    @objc private func routeChanged(_ notification: Notification) {
        checkCurrentRoute()
    }
    
    private func checkCurrentRoute() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        
        var foundBluetooth = false
        var foundTesla = false
        var deviceName: String?
        var portType = ""
        
        // Check outputs (A2DP speaker)
        for output in route.outputs {
            if isBluetoothPort(output.portType) {
                foundBluetooth = true
                deviceName = output.portName
                portType = output.portType.rawValue
                
                if isTeslaDevice(output.portName) {
                    foundTesla = true
                }
            }
        }
        
        // Check inputs (HFP mic)
        for input in route.inputs {
            if isBluetoothPort(input.portType) {
                foundBluetooth = true
                if deviceName == nil {
                    deviceName = input.portName
                    portType = input.portType.rawValue
                }
                
                if isTeslaDevice(input.portName) {
                    foundTesla = true
                }
            }
        }
        
        // Also check available inputs for Tesla even if not active
        if let availableInputs = session.availableInputs {
            for input in availableInputs {
                if isBluetoothPort(input.portType) && isTeslaDevice(input.portName) {
                    foundTesla = true
                    if deviceName == nil {
                        deviceName = input.portName
                    }
                }
            }
        }
        
        let wasConnected = isTeslaConnected
        
        DispatchQueue.main.async {
            self.isBluetoothConnected = foundBluetooth
            self.isTeslaConnected = foundTesla
            self.connectedDeviceName = deviceName
            self.bluetoothPortType = portType
        }
        
        // Fire events
        if foundTesla && !wasConnected {
            print("[BT] Tesla connected: \(deviceName ?? "unknown")")
            teslaConnected.send()
        } else if !foundTesla && wasConnected {
            print("[BT] Tesla disconnected")
            teslaDisconnected.send()
        }
    }
    
    // MARK: - Helpers
    
    private func isBluetoothPort(_ portType: AVAudioSession.Port) -> Bool {
        portType == .bluetoothA2DP ||
        portType == .bluetoothHFP ||
        portType == .bluetoothLE
    }
    
    private func isTeslaDevice(_ name: String) -> Bool {
        teslaIdentifiers.contains { identifier in
            name.localizedCaseInsensitiveContains(identifier)
        }
    }
    
    deinit {
        stopMonitoring()
    }
}
