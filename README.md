# Noia Voice 🎙️

A hands-free voice companion iOS app for talking to Noia (Clawdbot AI assistant) while driving. Routes audio through Tesla Bluetooth automatically.

## Architecture

```
Mic (BT/HFP) → VAD (energy-based) → Apple Speech (on-device) → WebSocket → Clawdbot Gateway
                                                                               ↓
Speaker (BT/A2DP) ← ElevenLabs TTS (streaming) ← Response chunks ← Agent (Noia)
```

## Features

- **Voice Activity Detection** — Energy-based with auto-calibration on ambient noise
- **On-device STT** — Apple Speech framework, zero cloud cost, works offline
- **Streaming TTS** — ElevenLabs turbo v2.5, sentence-level streaming for low latency
- **Tesla Bluetooth** — Auto-activates when connected to Tesla, routes audio through car speakers
- **Dark driving UI** — High contrast, large touch targets, auto-dim after inactivity
- **Audio cues** — "Acknowledged" beep and "still thinking" periodic tones
- **Interrupt support** — Tap to stop TTS and resume listening
- **Push-to-Talk or VAD** — Choose continuous listening or manual activation
- **Background audio** — Keeps running with screen off
- **Secure storage** — API keys in iOS Keychain, not UserDefaults

## Setup

### 1. Open in Xcode

```bash
open NoiaVoice.xcodeproj
```

Requires **Xcode 15.0+** and **iOS 17.0+ SDK**.

### 2. Configure Signing

1. Select the **NoiaVoice** target
2. Go to **Signing & Capabilities**
3. Select your **Development Team**
4. Change the **Bundle Identifier** if needed (e.g., `com.yourname.noiavoice`)

### 3. Build & Run

1. Connect your iPhone (iOS 17.0+)
2. Select your device as the build target
3. **⌘R** to build and run

### 4. Configure in App

On first launch, go to **Settings** (gear icon):

1. **Gateway Host** — Your Clawdbot server hostname (default: `noia-main`)
2. **Gateway Port** — Usually `18789`
3. **Bearer Token** — Your Clawdbot gateway auth token → **Save Token**
4. **ElevenLabs API Key** — Your ElevenLabs API key → **Save Key**
5. **Voice ID** — ElevenLabs voice ID (default is provided)
6. Adjust **VAD sensitivity** and **silence threshold** for your car environment

### 5. Start Listening

Tap the **Play** button on the main screen. The app will:
1. Calibrate the VAD on ambient noise (first 3 seconds — stay quiet)
2. Show a green pulsing mic icon when listening
3. Detect when you speak, transcribe on-device
4. Send to Clawdbot gateway, stream response via TTS

## Key Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Gateway Host | `noia-main` | Tailnet hostname of Clawdbot server |
| Gateway Port | `18789` | WebSocket port |
| Session Key | `voice-iphone` | Isolates voice conversations from other channels |
| Activation Mode | VAD | Continuous listening vs Push-to-Talk |
| VAD Sensitivity | Medium (0.5) | Lower = less sensitive to noise |
| Silence Threshold | 1.5s | How long to wait before ending utterance |
| Auto BT Activate | ON | Start listening when Tesla BT connects |
| TTS Speed | 1.0x | Playback speed |
| Auto-dim | 10s | Dim screen after inactivity |

## Technical Details

### Audio Pipeline
- **Capture**: `AVAudioEngine` with 1024-frame buffers (~64ms at 16kHz)
- **Session**: `.playAndRecord` category, `.voiceChat` mode, `.allowBluetooth`
- **VAD**: RMS energy in dB, auto-calibrated threshold, minimum speech frames before trigger
- **STT**: `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`
- **TTS**: ElevenLabs REST API, `eleven_turbo_v2_5` model, mp3_22050_32 format

### Gateway Protocol
- WebSocket connection to `wss://{host}:{port}/ws`
- `Authorization: Bearer {token}` header
- Sends: `{"type": "chat.message", "content": "...", "sessionKey": "voice-iphone"}`
- Receives: `chat.response.start`, `chat.response.chunk`, `chat.response.end`

### Background Modes
- `audio` — Keeps mic active with screen off
- `voip` — Maintains WebSocket connection

### Latency Budget
~5.3s from end of speech to first audio (see spec for optimization paths to ~3.5s)

## Files

```
NoiaVoice/
├── Sources/
│   ├── NoiaVoiceApp.swift          # App entry point
│   ├── ContentView.swift           # Main driving UI
│   ├── SettingsView.swift          # Configuration screen
│   ├── AudioCapture.swift          # AVAudioEngine mic capture
│   ├── VoiceActivityDetector.swift # Energy-based VAD
│   ├── SpeechRecognizer.swift      # Apple Speech STT
│   ├── GatewayClient.swift         # WebSocket client
│   ├── TTSEngine.swift             # ElevenLabs TTS
│   ├── BluetoothMonitor.swift      # Tesla BT detection
│   ├── ThinkingIndicator.swift     # Audio cues
│   ├── ConversationManager.swift   # Full flow orchestrator
│   ├── Models.swift                # Data models
│   ├── KeychainHelper.swift        # Secure storage
│   └── AppSettings.swift           # UserDefaults wrapper
├── Resources/
│   └── Info.plist                  # App configuration
└── Assets.xcassets/                # App icons, colors
```

## Permissions Required

- **Microphone** — Voice capture
- **Speech Recognition** — On-device transcription
- **Bluetooth** — Tesla connection detection
- **Background Audio** — Keep listening with screen off

## License

Private — Noia Voice © 2025
