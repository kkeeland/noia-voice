// ContentView.swift — Main driving mode UI
// Noia Voice © 2025

import SwiftUI

struct ContentView: View {
    @StateObject private var conversationManager = ConversationManager()
    @State private var showSettings = false
    @State private var isSessionActive = false
    @State private var dimOpacity: Double = 1.0
    @State private var dimTimer: Timer?
    @State private var lastInteraction = Date()
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Status bar
                statusBar
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                Spacer()
                
                // Main status icon
                statusIcon
                    .padding(.bottom, 24)
                
                // Status label
                Text(conversationManager.appState.displayLabel)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(statusColor)
                    .padding(.bottom, 24)
                
                // Transcript area
                transcriptArea
                    .padding(.horizontal, 20)
                
                Spacer()
                
                // Response area
                responseArea
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                
                // Control buttons
                controlBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .opacity(dimOpacity)
        .onTapGesture {
            resetDimTimer()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            startDimTimer()
            if conversationManager.settings.keepScreenOn {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    // MARK: - Status Bar
    
    private var statusBar: some View {
        HStack {
            // Connection indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)
                Text(conversationManager.connectionState.label)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Bluetooth indicator
            if conversationManager.isBluetoothConnected {
                HStack(spacing: 4) {
                    Image(systemName: "car.fill")
                        .font(.caption)
                    Text(conversationManager.bluetoothDeviceName ?? "BT")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
            
            Spacer()
            
            // Settings button
            Button {
                showSettings = true
                resetDimTimer()
            } label: {
                Image(systemName: "gear")
                    .font(.title3)
                    .foregroundColor(.gray)
                    .frame(width: 44, height: 44)
            }
        }
    }
    
    // MARK: - Status Icon
    
    private var statusIcon: some View {
        ZStack {
            // Pulsing glow when listening
            if conversationManager.appState == .listening {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 180, height: 180)
                    .modifier(PulsingModifier())
            }
            
            Circle()
                .fill(statusColor.opacity(0.2))
                .frame(width: 140, height: 140)
            
            Circle()
                .stroke(statusColor, lineWidth: 3)
                .frame(width: 140, height: 140)
            
            Image(systemName: conversationManager.appState.displayIcon)
                .font(.system(size: 52))
                .foregroundColor(statusColor)
        }
        .onTapGesture {
            handleMainTap()
            resetDimTimer()
        }
        .accessibilityLabel(conversationManager.appState.displayLabel)
    }
    
    // MARK: - Transcript Area
    
    private var transcriptArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !conversationManager.currentTranscript.isEmpty {
                Text("You said:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(conversationManager.currentTranscript)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 60)
    }
    
    // MARK: - Response Area
    
    private var responseArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !conversationManager.lastResponse.isEmpty {
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                ScrollView {
                    Text(conversationManager.lastResponse)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }
        }
    }
    
    // MARK: - Control Bar
    
    private var controlBar: some View {
        HStack(spacing: 40) {
            // Mute button
            Button {
                conversationManager.toggleMute()
                resetDimTimer()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: conversationManager.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.title2)
                    Text(conversationManager.isMuted ? "Unmute" : "Mute")
                        .font(.caption2)
                }
                .foregroundColor(conversationManager.isMuted ? .red : .white)
                .frame(width: 80, height: 60)
            }
            
            // Start/Stop button
            Button {
                toggleSession()
                resetDimTimer()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: isSessionActive ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                    Text(isSessionActive ? "Stop" : "Start")
                        .font(.caption2)
                }
                .foregroundColor(isSessionActive ? .red : .green)
                .frame(width: 80, height: 60)
            }
            
            // Pause/Resume button
            Button {
                if conversationManager.appState == .paused {
                    conversationManager.resumeListening()
                } else {
                    conversationManager.pauseSession()
                }
                resetDimTimer()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: conversationManager.appState == .paused ? "play.fill" : "pause.fill")
                        .font(.title2)
                    Text(conversationManager.appState == .paused ? "Resume" : "Pause")
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .frame(width: 80, height: 60)
            }
            .disabled(!isSessionActive)
            .opacity(isSessionActive ? 1.0 : 0.4)
        }
    }
    
    // MARK: - Push-to-Talk Overlay
    
    @ViewBuilder
    private var pushToTalkOverlay: some View {
        if conversationManager.settings.activationMode == .pushToTalk && isSessionActive {
            VStack {
                Spacer()
                Text("Hold to Talk")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 100)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var statusColor: Color {
        switch conversationManager.appState {
        case .idle: return .gray
        case .listening: return .green
        case .processing: return .blue
        case .thinking: return .orange
        case .speaking: return .purple
        case .paused: return .yellow
        case .error: return .red
        }
    }
    
    private var connectionColor: Color {
        switch conversationManager.connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .red
        }
    }
    
    private func handleMainTap() {
        if conversationManager.settings.activationMode == .pushToTalk {
            // For PTT, the main icon area acts as the talk button
            // In a real implementation, use long-press gesture
        } else {
            // In VAD mode, tapping interrupts if speaking
            if conversationManager.appState == .speaking {
                conversationManager.interruptSpeaking()
            }
        }
    }
    
    private func toggleSession() {
        if isSessionActive {
            conversationManager.stopSession()
            isSessionActive = false
        } else {
            conversationManager.startSession()
            isSessionActive = true
        }
    }
    
    // MARK: - Auto-Dim
    
    private func startDimTimer() {
        let interval = conversationManager.settings.autoDimSeconds
        guard interval > 0 else { return }
        
        dimTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 1.0)) {
                dimOpacity = 0.3
            }
        }
    }
    
    private func resetDimTimer() {
        dimTimer?.invalidate()
        withAnimation(.easeInOut(duration: 0.3)) {
            dimOpacity = 1.0
        }
        startDimTimer()
        lastInteraction = Date()
    }
}

// MARK: - Pulsing Animation Modifier

struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .opacity(isPulsing ? 0.3 : 0.6)
            .animation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
