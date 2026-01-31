# Voice Notes Feature Design - v1

**Author**: worker-proposer
**Date**: 2025-01-31
**Status**: Proposal (awaiting critique)

---

## 1. Overview

This proposal outlines the implementation of a voice note feature for CMUX that allows users to record audio messages, transcribe them automatically, and send the transcribed text as messages to the supervisor agent.

### Core Use Case

```
User presses record → speaks → stops recording →
audio transcribed → text sent to supervisor as message
```

### Goals

- Seamless voice input alongside existing text input
- Fast, accurate transcription
- Minimal latency between recording end and message delivery
- Graceful error handling for microphone/transcription failures

---

## 2. User Experience Flow

### 2.1 Recording States

```
[Idle] → (click mic) → [Recording] → (click stop) → [Transcribing] → [Sent/Error]
```

### 2.2 UI Behavior

1. **Idle**: Microphone button appears next to send button in ChatInput
2. **Recording**:
   - Button pulses red to indicate active recording
   - Timer shows recording duration
   - Waveform visualization shows audio levels
   - User can cancel by pressing Escape or clicking cancel
3. **Transcribing**:
   - Spinner indicates processing
   - Recording preview shows duration of captured audio
4. **Complete**:
   - Transcribed text appears in input field (editable before sending)
   - User can send or discard

### 2.3 Keyboard Shortcuts

- `Cmd/Ctrl + Shift + V`: Toggle recording (start/stop)
- `Escape`: Cancel current recording
- `Enter`: Send transcribed message (when in input field)

---

## 3. Technical Architecture

### 3.1 System Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              FRONTEND                                    │
│                                                                          │
│  ┌────────────────┐    ┌─────────────────┐    ┌────────────────────┐    │
│  │ VoiceRecorder  │───▶│ MediaRecorder   │───▶│ AudioBlob (webm)   │    │
│  │ Component      │    │ API             │    │                    │    │
│  └────────────────┘    └─────────────────┘    └─────────┬──────────┘    │
│                                                          │               │
│                                          POST /api/voice/transcribe     │
│                                                          │               │
└──────────────────────────────────────────────────────────┼───────────────┘
                                                           │
┌──────────────────────────────────────────────────────────┼───────────────┐
│                              BACKEND                      ▼               │
│                                                                          │
│  ┌─────────────────┐    ┌──────────────────┐    ┌────────────────────┐  │
│  │ voice_routes.py │───▶│ VoiceService     │───▶│ Transcription      │  │
│  │                 │    │                  │    │ Provider           │  │
│  └─────────────────┘    └──────────────────┘    └────────────────────┘  │
│                                │                                         │
│                                ▼                                         │
│                         ┌──────────────────┐                            │
│                         │ MailboxService   │                            │
│                         │ (send to super)  │                            │
│                         └──────────────────┘                            │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Component Breakdown

#### Frontend

| Component | Responsibility |
|-----------|---------------|
| `VoiceRecorder` | Recording UI, microphone access, state management |
| `AudioVisualizer` | Real-time waveform display during recording |
| `useVoiceRecording` | Hook for MediaRecorder API abstraction |
| `voiceStore` | Zustand store for recording state |

#### Backend

| Component | Responsibility |
|-----------|---------------|
| `voice_routes.py` | REST endpoints for voice operations |
| `VoiceService` | Audio processing, transcription orchestration |
| `TranscriptionProvider` | Abstract interface for transcription backends |

---

## 4. Frontend Implementation

### 4.1 VoiceRecorder Component

```tsx
// src/frontend/src/components/chat/VoiceRecorder.tsx

interface VoiceRecorderProps {
  onTranscript: (text: string) => void;
  disabled?: boolean;
}

// States: idle | requesting | recording | transcribing | error
```

**Key Features**:
- Requests microphone permission on first use
- Uses MediaRecorder API with webm/opus codec
- Streams audio data to ArrayBuffer chunks
- Converts to Blob for upload

### 4.2 Audio Visualization

```tsx
// src/frontend/src/components/chat/AudioVisualizer.tsx

// Uses Web Audio API's AnalyserNode
// Renders canvas-based waveform
// Updates at 60fps during recording
```

### 4.3 useVoiceRecording Hook

```typescript
// src/frontend/src/hooks/useVoiceRecording.ts

interface UseVoiceRecordingReturn {
  isRecording: boolean;
  isTranscribing: boolean;
  duration: number;
  error: string | null;
  audioLevel: number; // 0-1 for visualization

  startRecording: () => Promise<void>;
  stopRecording: () => Promise<Blob>;
  cancelRecording: () => void;
}
```

### 4.4 Integration with ChatInput

Modify existing `ChatInput.tsx`:

```tsx
<div className="flex gap-2 items-end">
  <Textarea ... />
  <VoiceRecorder
    onTranscript={(text) => setMessage(prev => prev + text)}
    disabled={isPending}
  />
  <Button onClick={handleSubmit} ...>
    <Send />
  </Button>
</div>
```

### 4.5 Zustand Store

```typescript
// src/frontend/src/stores/voiceStore.ts

interface VoiceState {
  status: 'idle' | 'requesting' | 'recording' | 'transcribing' | 'error';
  duration: number;
  error: string | null;
  hasPermission: boolean | null;

  setStatus: (status: VoiceState['status']) => void;
  setDuration: (duration: number) => void;
  setError: (error: string | null) => void;
  setHasPermission: (has: boolean) => void;
  reset: () => void;
}
```

---

## 5. Backend Implementation

### 5.1 Voice Routes

```python
# src/server/routes/voice.py

router = APIRouter()

@router.post("/transcribe")
async def transcribe_audio(
    audio: UploadFile,
    send_immediately: bool = Query(default=False),
    target_agent: str = Query(default="supervisor")
) -> TranscriptionResponse:
    """
    Transcribe uploaded audio file.

    Args:
        audio: Audio file (webm, mp3, wav, m4a)
        send_immediately: If True, send transcription to target_agent
        target_agent: Agent to receive the message

    Returns:
        TranscriptionResponse with text and metadata
    """

@router.get("/status")
async def get_voice_status() -> VoiceStatusResponse:
    """Check if voice service is available and configured."""
```

### 5.2 Voice Service

```python
# src/server/services/voice.py

class VoiceService:
    def __init__(self):
        self.provider = self._init_provider()
        self.temp_dir = Path(".cmux/voice_temp")

    async def transcribe(
        self,
        audio_data: bytes,
        format: str = "webm"
    ) -> TranscriptionResult:
        """Transcribe audio bytes to text."""

    async def cleanup_temp_files(self, max_age_seconds: int = 3600):
        """Remove temporary audio files older than max_age."""
```

### 5.3 Transcription Provider Interface

```python
# src/server/services/transcription/base.py

from abc import ABC, abstractmethod

class TranscriptionProvider(ABC):
    @abstractmethod
    async def transcribe(
        self,
        audio_path: Path,
        language: str = "en"
    ) -> TranscriptionResult:
        """Transcribe audio file to text."""

    @abstractmethod
    def is_available(self) -> bool:
        """Check if provider is configured and available."""
```

### 5.4 Transcription Providers

**Option A: OpenAI Whisper API (Recommended for v1)**

```python
# src/server/services/transcription/openai_whisper.py

class OpenAIWhisperProvider(TranscriptionProvider):
    def __init__(self):
        self.client = OpenAI()  # Uses OPENAI_API_KEY env var

    async def transcribe(self, audio_path: Path, language: str = "en"):
        with open(audio_path, "rb") as f:
            response = await self.client.audio.transcriptions.create(
                model="whisper-1",
                file=f,
                language=language
            )
        return TranscriptionResult(
            text=response.text,
            confidence=None,  # Whisper API doesn't return confidence
            duration=None
        )
```

**Option B: Local Whisper (Future)**

```python
# src/server/services/transcription/local_whisper.py

class LocalWhisperProvider(TranscriptionProvider):
    """Uses whisper.cpp or faster-whisper for local transcription."""
```

---

## 6. API Specification

### 6.1 POST /api/voice/transcribe

**Request**:
```
Content-Type: multipart/form-data

audio: <binary audio data>
```

**Query Parameters**:
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `send_immediately` | bool | false | Send to supervisor after transcription |
| `target_agent` | string | "supervisor" | Agent to receive message |
| `language` | string | "en" | ISO 639-1 language code |

**Response (200)**:
```json
{
  "success": true,
  "text": "transcribed text here",
  "duration_seconds": 4.2,
  "message_id": "uuid-if-sent-immediately"
}
```

**Response (400 - Bad Request)**:
```json
{
  "success": false,
  "error": "unsupported_format",
  "message": "Audio format 'xyz' is not supported"
}
```

**Response (503 - Service Unavailable)**:
```json
{
  "success": false,
  "error": "transcription_unavailable",
  "message": "Transcription service is not configured"
}
```

### 6.2 GET /api/voice/status

**Response (200)**:
```json
{
  "available": true,
  "provider": "openai_whisper",
  "supported_formats": ["webm", "mp3", "wav", "m4a", "ogg"],
  "max_duration_seconds": 300,
  "max_file_size_mb": 25
}
```

---

## 7. Data Models

```python
# src/server/models/voice.py

class TranscriptionResult(BaseModel):
    text: str
    duration_seconds: Optional[float] = None
    confidence: Optional[float] = None
    language: Optional[str] = None

class TranscriptionResponse(BaseModel):
    success: bool
    text: Optional[str] = None
    duration_seconds: Optional[float] = None
    message_id: Optional[str] = None
    error: Optional[str] = None
    message: Optional[str] = None

class VoiceStatusResponse(BaseModel):
    available: bool
    provider: Optional[str] = None
    supported_formats: List[str] = []
    max_duration_seconds: int = 300
    max_file_size_mb: int = 25
```

---

## 8. Configuration

```python
# src/server/config.py (additions)

class Settings(BaseSettings):
    # ... existing settings ...

    # Voice settings
    voice_enabled: bool = True
    voice_provider: str = "openai_whisper"  # or "local_whisper"
    voice_max_duration_seconds: int = 300  # 5 minutes
    voice_max_file_size_mb: int = 25
    voice_temp_cleanup_interval: int = 3600  # seconds

    # OpenAI Whisper settings (if using)
    openai_api_key: Optional[str] = None  # Falls back to OPENAI_API_KEY env
```

---

## 9. Error Handling

### 9.1 Frontend Errors

| Error | User Message | Recovery |
|-------|--------------|----------|
| Microphone denied | "Microphone access denied. Please allow access in browser settings." | Show settings link |
| No microphone | "No microphone found. Please connect a microphone." | - |
| Recording failed | "Recording failed. Please try again." | Retry button |
| Upload failed | "Failed to upload audio. Please check your connection." | Retry button |
| Transcription failed | "Could not transcribe audio. Please try again or type your message." | Fall back to text input |

### 9.2 Backend Errors

| Error | HTTP Status | Response |
|-------|-------------|----------|
| Invalid audio format | 400 | `{"error": "unsupported_format"}` |
| File too large | 413 | `{"error": "file_too_large"}` |
| Duration too long | 400 | `{"error": "duration_exceeded"}` |
| Transcription service down | 503 | `{"error": "transcription_unavailable"}` |
| Transcription failed | 500 | `{"error": "transcription_failed"}` |

---

## 10. Security Considerations

### 10.1 Audio Data Handling

- Audio files are stored temporarily in `.cmux/voice_temp/` (gitignored)
- Files are deleted after transcription completes
- Hourly cleanup job removes orphaned files
- No audio is persisted long-term (only transcribed text)

### 10.2 API Security

- Rate limiting: Max 10 transcription requests per minute per session
- File size limit: 25MB max
- Duration limit: 5 minutes max
- Format validation: Only allow known audio formats

### 10.3 Privacy

- Audio is sent to external API (OpenAI) for transcription
- Should display notice to user before first use
- Consider local Whisper option for privacy-sensitive deployments

---

## 11. File Structure

```
src/
├── frontend/src/
│   ├── components/chat/
│   │   ├── VoiceRecorder.tsx      # New - recording UI
│   │   ├── AudioVisualizer.tsx    # New - waveform display
│   │   └── ChatInput.tsx          # Modified - add voice button
│   ├── hooks/
│   │   └── useVoiceRecording.ts   # New - MediaRecorder abstraction
│   └── stores/
│       └── voiceStore.ts          # New - recording state
│
├── server/
│   ├── routes/
│   │   └── voice.py               # New - voice endpoints
│   ├── services/
│   │   ├── voice.py               # New - voice service
│   │   └── transcription/
│   │       ├── __init__.py        # New
│   │       ├── base.py            # New - provider interface
│   │       └── openai_whisper.py  # New - OpenAI provider
│   └── models/
│       └── voice.py               # New - voice models
│
└── .cmux/
    └── voice_temp/                # Runtime - temporary audio files
```

---

## 12. Implementation Plan

### Phase 1: Core Infrastructure (MVP)

1. Backend voice service and OpenAI Whisper integration
2. Basic `POST /api/voice/transcribe` endpoint
3. Frontend `useVoiceRecording` hook
4. Simple `VoiceRecorder` button component
5. Integration with ChatInput

### Phase 2: Polish

1. Audio visualization during recording
2. Recording timer
3. Keyboard shortcuts
4. Error handling and retry logic
5. Permission flow

### Phase 3: Future Enhancements

1. Local Whisper option for privacy
2. Real-time streaming transcription
3. Voice activity detection (auto-stop)
4. Multi-language support
5. Voice message playback (store audio with transcript)

---

## 13. Testing Strategy

### Unit Tests

- `test_voice_service.py`: Transcription service mocking
- `test_voice_routes.py`: API endpoint tests
- `VoiceRecorder.test.tsx`: Component tests

### Integration Tests

- End-to-end recording → transcription → message flow
- Error scenarios (permission denied, service unavailable)
- File cleanup verification

### Manual Testing

- Test on Chrome, Firefox, Safari (WebRTC compatibility)
- Test with different microphones
- Test with accents and languages
- Test network interruptions

---

## 14. Dependencies

### Frontend

```json
{
  "dependencies": {
    // No new dependencies - uses native MediaRecorder and Web Audio APIs
  }
}
```

### Backend

```toml
[project.dependencies]
openai = ">=1.0.0"  # For Whisper API
python-multipart = "*"  # For file uploads (may already be present)
```

---

## 15. Open Questions

1. **Streaming vs. batch transcription**: Should we stream audio during recording for faster results? (Adds complexity, better UX)

2. **Audio storage**: Should we keep audio files for playback, or only store transcripts? (Privacy vs. UX tradeoff)

3. **Default behavior**: Should transcribed text auto-send, or appear in input for review? (Proposed: appear in input)

4. **Mobile support**: Do we need to consider mobile browsers? (MediaRecorder support varies)

5. **Fallback provider**: What if OpenAI is unavailable? (Local Whisper? Error only?)

---

## 16. Success Metrics

- **Latency**: < 3 seconds from recording stop to transcript appearing
- **Accuracy**: Subjectively usable for English speech
- **Reliability**: < 1% transcription failures for valid audio
- **Adoption**: Track voice vs. text message ratio (if metrics exist)

---

*End of proposal - awaiting critique from worker-critic*
