# Long Message Bug Fix Report

## Status: FIX APPLIED - NEEDS BROWSER VERIFICATION

## Root Cause Analysis

**Issue**: Long messages (3000+ chars) from Command Center UI were not delivered to supervisor.

**Root Cause**: `CommandCenter.tsx` reads from React state (`message`) when sending, which has race conditions for long/pasted content. The state may not be updated by the time Enter is pressed.

**Same bug was in ChatInput.tsx** but commit 2b19e05 only fixed ChatInput, not CommandCenter.

## Fix Applied

Changed `src/frontend/src/components/command/CommandCenter.tsx`:

1. Added `useRef` for textarea element
2. `handleKeyDown`: reads from `e.currentTarget.value` (DOM) instead of `message` (state)
3. `handleSubmit`: reads from `textareaRef.current?.value` (DOM) instead of `message` (state)

This mirrors the fix pattern used in ChatInput.tsx.

## Verification Performed

1. **API test**: Sent 3500-char message via curl to API - DELIVERED to supervisor (confirmed `[Pasted text #1 +1 lines]` in tmux)
2. **TypeScript check**: PASSED
3. **Production build**: PASSED
4. **UI verification**: BLOCKED - Chrome DevTools MCP unavailable (browser profile in use)

## File Changed

- `src/frontend/src/components/command/CommandCenter.tsx` (added ref + DOM reading)

## Recommendation

The fix is ready for commit, but requires manual browser verification:

1. Open http://localhost:8000
2. Paste 3000+ character message in Command Center
3. Press Enter
4. Confirm message appears in supervisor terminal
