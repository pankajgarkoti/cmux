# Voice Notes Feature - FINAL DESIGN v2

**Authors**: worker-proposer (original), worker-critic (critique)
**Date**: 2025-01-31
**Status**: CONVERGED - Ready for implementation

---

## Critique Response

The critic is right. I over-engineered a 100-line feature into 500+ lines.

### Accepted (All Major Points)

| Cut Item                  | Reason I Accept                   |
| ------------------------- | --------------------------------- |
| AudioVisualizer           | CSS pulse animation is sufficient |
| Zustand voiceStore        | useState handles 3 states fine    |
| useVoiceRecording hook    | Premature abstraction             |
| TranscriptionProvider ABC | YAGNI - one provider              |
| VoiceService class        | Route handler is enough           |
| GET /api/voice/status     | Handle errors when they happen    |
| send_immediately param    | Not the use case                  |
| target_agent param        | Not the use case                  |
| Language parameter        | Whisper auto-detects              |
| Rate limiting             | Local dev tool                    |
| Cleanup job               | Delete immediately                |
| 5 config options          | Just need OPENAI_API_KEY          |
| 3-phase plan              | Just implement it                 |
| Testing strategy          | Write with code                   |
| Success metrics           | Ship and see                      |

### Defended (Minor Additions)

| Item                             | Why Keep It                                |
| -------------------------------- | ------------------------------------------ |
| Escape to cancel                 | 1 line of code, prevents accidental sends  |
| Error toast                      | User needs to know if transcription failed |
| Disabled state during transcribe | Prevent double-clicks                      |

These add ~10 lines total. Worth it.

---

## Final Implementation

### Files Changed

```
src/frontend/src/components/chat/VoiceButton.tsx  (NEW - 70 lines)
src/frontend/src/components/chat/ChatInput.tsx    (MODIFY - 3 lines)
src/server/routes/voice.py                        (NEW - 25 lines)
src/server/main.py                                (MODIFY - 2 lines)
```

**Total: ~100 lines of new code**

---

### Frontend: VoiceButton.tsx

```tsx
import { useState, useRef, useCallback, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Mic, Square, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

interface VoiceButtonProps {
  onTranscript: (text: string) => void;
  onError?: (error: string) => void;
  disabled?: boolean;
}

export function VoiceButton({
  onTranscript,
  onError,
  disabled,
}: VoiceButtonProps) {
  const [state, setState] = useState<"idle" | "recording" | "transcribing">(
    "idle",
  );
  const mediaRecorder = useRef<MediaRecorder | null>(null);
  const chunks = useRef<Blob[]>([]);

  const stop = useCallback(
    async (cancelled = false) => {
      if (!mediaRecorder.current || state !== "recording") return;

      mediaRecorder.current.stream.getTracks().forEach((t) => t.stop());

      if (cancelled) {
        setState("idle");
        return;
      }

      setState("transcribing");
      mediaRecorder.current.stop();

      await new Promise<void>((r) => {
        mediaRecorder.current!.onstop = () => r();
      });
      const blob = new Blob(chunks.current, { type: "audio/webm" });

      try {
        const form = new FormData();
        form.append("audio", blob);
        const res = await fetch("/api/voice/transcribe", {
          method: "POST",
          body: form,
        });

        if (!res.ok) {
          throw new Error(
            res.status === 503
              ? "Voice transcription not configured"
              : "Transcription failed",
          );
        }

        const { text, error } = await res.json();
        if (error) throw new Error(error);
        if (text) onTranscript(text);
      } catch (e) {
        onError?.(e instanceof Error ? e.message : "Transcription failed");
      } finally {
        setState("idle");
      }
    },
    [state, onTranscript, onError],
  );

  const start = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      mediaRecorder.current = new MediaRecorder(stream);
      chunks.current = [];
      mediaRecorder.current.ondataavailable = (e) =>
        chunks.current.push(e.data);
      mediaRecorder.current.start();
      setState("recording");
    } catch {
      onError?.("Microphone access denied");
    }
  };

  // Escape to cancel
  useEffect(() => {
    if (state !== "recording") return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") stop(true);
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [state, stop]);

  const isRecording = state === "recording";
  const isTranscribing = state === "transcribing";

  return (
    <Button
      type="button"
      variant={isRecording ? "destructive" : "outline"}
      size="icon"
      onClick={isRecording ? () => stop(false) : start}
      disabled={disabled || isTranscribing}
      className={cn("h-11 w-11 flex-shrink-0", isRecording && "animate-pulse")}
      title={
        isRecording ? "Stop recording (Esc to cancel)" : "Record voice message"
      }
    >
      {isTranscribing ? (
        <Loader2 className="h-4 w-4 animate-spin" />
      ) : isRecording ? (
        <Square className="h-4 w-4" />
      ) : (
        <Mic className="h-4 w-4" />
      )}
    </Button>
  );
}
```

---

### Frontend: ChatInput.tsx Changes

```diff
 import { Textarea } from '@/components/ui/textarea';
 import { Button } from '@/components/ui/button';
 import { Send, Loader2 } from 'lucide-react';
+import { VoiceButton } from './VoiceButton';
+import { toast } from 'sonner'; // or your toast library

 // ... existing code ...

 return (
   <div className="p-4 border-t bg-background/50 backdrop-blur-sm">
     <div className="flex gap-2 items-end">
       <Textarea ... />
+      <VoiceButton
+        onTranscript={(text) => setMessage(prev => prev ? prev + ' ' + text : text)}
+        onError={(err) => toast.error(err)}
+        disabled={isPending}
+      />
       <Button onClick={handleSubmit} ...>
```

---

### Backend: voice.py

```python
import os
import tempfile
from fastapi import APIRouter, UploadFile, HTTPException
from openai import OpenAI, OpenAIError

router = APIRouter()

@router.post("/transcribe")
async def transcribe(audio: UploadFile):
    """Transcribe audio to text using OpenAI Whisper."""

    # Check for API key
    if not os.environ.get("OPENAI_API_KEY"):
        raise HTTPException(503, detail="OPENAI_API_KEY not configured")

    client = OpenAI()

    # Save to temp file (Whisper API needs a file object)
    with tempfile.NamedTemporaryFile(suffix=".webm", delete=False) as f:
        f.write(await audio.read())
        temp_path = f.name

    try:
        with open(temp_path, "rb") as f:
            result = client.audio.transcriptions.create(model="whisper-1", file=f)
        return {"text": result.text}
    except OpenAIError as e:
        raise HTTPException(500, detail=str(e))
    finally:
        os.unlink(temp_path)
```

---

### Backend: main.py Changes

```diff
 from .routes import agents, messages, webhooks, journal, filesystem, agent_events, sessions
+from .routes import voice

 # ... existing code ...

 app.include_router(sessions.router, prefix="/api/sessions", tags=["sessions"])
+app.include_router(voice.router, prefix="/api/voice", tags=["voice"])
```

---

## Behavior

1. User clicks mic button → microphone permission requested
2. User speaks → button pulses red, shows stop icon
3. User clicks stop → spinner shown, audio sent to backend
4. Backend transcribes via Whisper → returns text
5. Text appears in input field → user can edit/send
6. User presses Escape during recording → cancels without transcribing

## Error States

| Error                  | Display                                     |
| ---------------------- | ------------------------------------------- |
| Microphone denied      | Toast: "Microphone access denied"           |
| OPENAI_API_KEY missing | Toast: "Voice transcription not configured" |
| Transcription fails    | Toast: "Transcription failed"               |

## Dependencies

**Frontend**: None new (uses existing Button, lucide-react icons)
**Backend**: `openai>=1.0.0` (add to pyproject.toml if not present)

---

## What We're NOT Building (Deferred)

- Waveform visualization
- Recording timer
- Keyboard shortcut to start recording
- Language selection
- Local Whisper fallback
- Audio playback
- Rate limiting
- Configuration options

These can be added if users request them.

---

## Implementation Checklist

- [ ] Create `src/frontend/src/components/chat/VoiceButton.tsx`
- [ ] Modify `src/frontend/src/components/chat/ChatInput.tsx` to include VoiceButton
- [ ] Create `src/server/routes/voice.py`
- [ ] Modify `src/server/main.py` to include voice router
- [ ] Ensure `openai` is in dependencies
- [ ] Test: record → transcribe → appears in input
- [ ] Test: cancel with Escape
- [ ] Test: error when no API key

---

_Converged design complete. Ready for implementation._
