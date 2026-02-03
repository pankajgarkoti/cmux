# UI/UX Implementation Plan - Defender's Position

**Author:** ui-defender
**Date:** 2026-02-01
**Status:** Initial Draft for Debate

---

## Executive Summary

This plan addresses 7 UI/UX improvements for the CMUX dashboard, grounded in the actual codebase structure. Each improvement is designed to be minimal, focused, and avoid over-engineering.

---

## 1. Mailbox Archival & Cleaning

### Current State
- `.cmux/mailbox` is an append-only file (currently 36KB)
- Router tracks position via `.cmux/.router_line`
- Messages also persist to SQLite (`conversations.db`) via `MailboxService.store_message()`

### Proposed Approach

**Strategy: Daily rotation with simple cleanup script**

```bash
# src/orchestrator/lib/mailbox_rotate.sh
rotate_mailbox() {
    local mailbox=".cmux/mailbox"
    local archive_dir=".cmux/journal/$(date +%Y-%m-%d)/archives"

    mkdir -p "$archive_dir"

    # Archive if > 50KB or > 1000 lines
    if [[ $(wc -l < "$mailbox") -gt 1000 ]] || [[ $(stat -f%z "$mailbox") -gt 51200 ]]; then
        mv "$mailbox" "$archive_dir/mailbox-$(date +%H%M%S).bak"
        touch "$mailbox"
        echo "0" > .cmux/.router_line  # Reset position tracker
    fi
}
```

**When:** Call from `health.sh` every health check (every 10 seconds, but rotation only triggers when thresholds met)

**Why this approach:**
- Simple shell script, consistent with existing orchestration patterns
- Archives to journal (already has date-based structure)
- Resets router position to avoid stale offset issues
- SQLite has the real message history; mailbox is just a queue

**Files to modify:**
- `src/orchestrator/lib/mailbox_rotate.sh` (new)
- `src/orchestrator/health.sh` (add rotation call)

---

## 2. File Tree Items Unfolded by Default

### Current State
```typescript
// src/frontend/src/components/explorer/FileTree.tsx:53
const [isOpen, setIsOpen] = useState(level < 2);
```

Currently: Unfolds first 2 levels by default.

### Proposed Change

**Option A: Always unfold (simple)**
```typescript
const [isOpen, setIsOpen] = useState(true);
```

**Option B: Unfold based on item count (smarter)**
```typescript
const [isOpen, setIsOpen] = useState(() => {
  // Always unfold if directory has < 10 items
  const itemCount = item.children?.length || 0;
  return itemCount < 10 || level < 2;
});
```

**Recommended: Option A** - The .cmux directory is small and users want to see everything. Keep it simple.

**Files to modify:**
- `src/frontend/src/components/explorer/FileTree.tsx` (line 53)

---

## 3. Display Non-Text Assets (PNGs, etc.)

### Current State
`MemoryViewer.tsx` handles `.md`, `.log`, and defaults to `<pre>` for other text.

### Proposed Approach

**Add image detection and inline display:**

```typescript
// src/frontend/src/components/explorer/MemoryViewer.tsx

// Add file type detection
const isImage = /\.(png|jpg|jpeg|gif|webp|svg)$/i.test(file.name);
const isPdf = file.name.endsWith('.pdf');

// Modify content section
if (isImage) {
  return (
    <div className="flex-1 flex items-center justify-center p-4 bg-muted/30">
      <img
        src={`${API_BASE}/api/filesystem/content?path=${encodeURIComponent(file.path)}&raw=true`}
        alt={file.name}
        className="max-w-full max-h-full object-contain rounded-lg shadow-sm"
      />
    </div>
  );
}
```

**Backend change needed:**
```python
# src/server/routes/filesystem.py
@router.get("/content")
async def get_file_content(path: str, raw: bool = False):
    # ... existing path validation ...

    if raw:
        # Return raw binary for images
        media_type = mimetypes.guess_type(path)[0] or "application/octet-stream"
        return FileResponse(full_path, media_type=media_type)

    # Existing text content logic...
```

**Files to modify:**
- `src/frontend/src/components/explorer/MemoryViewer.tsx`
- `src/server/routes/filesystem.py` (add raw mode)

---

## 4. Mailbox Display Improvements

### Current State
`MailboxSection` in `Explorer.tsx` (lines 601-701) shows recent messages as clickable items.

### Problems:
1. Messages appear clickable but don't navigate anywhere useful
2. No syntax highlighting for mailbox file content
3. Confusing interaction model

### Proposed Approach

**A. Remove clickable message items, simplify to status-only display:**

```typescript
// Explorer.tsx - MailboxSection
<CollapsibleContent className="mt-1">
  {/* Just show recent messages as status info, not clickable */}
  {isLoading ? (
    <Skeleton className="h-4 w-full mx-3" />
  ) : recentMessages.length > 0 ? (
    <div className="space-y-1 px-3 py-1">
      {recentMessages.slice(0, 5).map((msg) => (
        <div key={msg.id} className="flex items-start gap-2 text-xs text-muted-foreground">
          <span className="font-mono">{msg.from_agent}</span>
          <span>→</span>
          <span className="font-mono">{msg.to_agent}</span>
          <span className="truncate flex-1 text-foreground/70">
            {parseSubject(msg.content)}
          </span>
        </div>
      ))}
    </div>
  ) : (
    <p className="px-3 py-2 text-xs text-muted-foreground">No recent messages</p>
  )}

  {/* View raw mailbox button - opens in MemoryViewer with highlighting */}
  {mailboxItem && (
    <button
      onClick={() => handleFileSelect(mailboxItem)}
      className="w-full text-left px-3 py-1.5 text-xs text-blue-400 hover:underline"
    >
      View full mailbox →
    </button>
  )}
</CollapsibleContent>
```

**B. Add syntax highlighting for mailbox file in MemoryViewer:**

```typescript
// MemoryViewer.tsx
const isMailbox = file.name === 'mailbox';

if (isMailbox) {
  return <MailboxViewer content={content || ''} />;
}

function MailboxViewer({ content }: { content: string }) {
  const lines = content.split('\n').filter(Boolean);
  return (
    <div className="font-mono text-xs space-y-1 p-3">
      {lines.map((line, i) => {
        // Parse: [timestamp] from -> to: subject
        const match = line.match(/^\[([^\]]+)\] ([^ ]+) -> ([^:]+): (.+)$/);
        if (!match) return <div key={i} className="text-muted-foreground">{line}</div>;

        const [, timestamp, from, to, subject] = match;
        return (
          <div key={i} className="flex gap-2 items-start">
            <span className="text-muted-foreground shrink-0">[{timestamp.split('T')[1]?.slice(0,8)}]</span>
            <span className="text-blue-400 shrink-0">{from.split(':').pop()}</span>
            <span className="text-muted-foreground">→</span>
            <span className="text-green-400 shrink-0">{to.split(':').pop()}</span>
            <span className="text-foreground truncate">{subject}</span>
          </div>
        );
      })}
    </div>
  );
}
```

**Files to modify:**
- `src/frontend/src/components/explorer/Explorer.tsx` (MailboxSection)
- `src/frontend/src/components/explorer/MemoryViewer.tsx` (add MailboxViewer)

---

## 5. router.log Analysis

### Current State
```bash
$ wc -l .cmux/router.log
# 47KB, logging every parse/route operation
```

**Usage:**
- `router.sh` logs to it (parse success/fail, delivery status)
- `monitor.sh` references it but doesn't use it for anything
- Not displayed in UI anywhere
- Not used by health checks

### Recommendation: **Keep but reduce verbosity**

**Reasoning:**
- Valuable for debugging routing issues (e.g., the colon parsing bug found earlier)
- But current logging is excessive (logs every successful parse)

**Proposed change:**
```bash
# router.sh - Only log failures and important events
log_route() {
    local status="$1"
    # Only log failures and startups, not successful operations
    case "$status" in
        FAILED|PARSE_FAIL|WARN|STARTUP)
            echo "$(date -Iseconds) | $status | $2 -> $3 | ${4:-}" >> "$CMUX_ROUTER_LOG"
            ;;
    esac
}
```

**Add rotation to prevent growth:**
```bash
# In health.sh or cmux.sh startup
if [[ -f .cmux/router.log ]] && [[ $(stat -f%z .cmux/router.log) -gt 102400 ]]; then
    mv .cmux/router.log .cmux/router.log.old
    touch .cmux/router.log
fi
```

**Files to modify:**
- `src/orchestrator/router.sh` (reduce logging verbosity)
- `src/orchestrator/health.sh` (add rotation)

---

## 6. Agent Realtime Status Improvements

### 6a. Show Tool Calls in Chat Space

**Current State:**
- `AgentActivityIndicator.tsx` shows a simple bar with "Reading files" etc.
- Tool call details only in Activity panel

**Proposed Enhancement:**

Keep the simple indicator but add expandable detail:

```typescript
// AgentActivityIndicator.tsx
export function AgentActivityIndicator({ agentId, className }: Props) {
  const [showDetails, setShowDetails] = useState(false);
  // ... existing logic ...

  return (
    <div className={cn('border-t bg-muted/30', className)}>
      <button
        onClick={() => setShowDetails(!showDetails)}
        className="w-full flex items-center gap-2 px-4 py-2 text-sm text-muted-foreground hover:bg-muted/50"
      >
        <Loader2 className="h-4 w-4 animate-spin text-primary" />
        <span className="font-medium text-foreground/80">{description}</span>
        <ChevronDown className={cn('h-4 w-4 ml-auto transition-transform', showDetails && 'rotate-180')} />
      </button>

      {showDetails && latestActiveEvent && (
        <div className="px-4 pb-2 text-xs font-mono bg-muted/20">
          <div className="text-muted-foreground">Tool: {latestActiveEvent.tool_name}</div>
          {latestActiveEvent.tool_input && (
            <pre className="mt-1 text-[10px] max-h-20 overflow-auto">
              {JSON.stringify(latestActiveEvent.tool_input, null, 2)}
            </pre>
          )}
        </div>
      )}
    </div>
  );
}
```

### 6b. Tooltips on Agent Hover in Sidebar

**Current State:**
- `AgentItem` in `Explorer.tsx` has no tooltips
- `AgentTreeItem.tsx` exists but isn't used in main Explorer

**Proposed Enhancement:**

```typescript
// Explorer.tsx - AgentItem function (line 558+)
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';

function AgentItem({ agent, isSelected, onClick }: Props) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <button
          onClick={onClick}
          className={cn(/* existing classes */)}
        >
          {/* existing content */}
        </button>
      </TooltipTrigger>
      <TooltipContent side="right" className="max-w-xs">
        <div className="space-y-1">
          <div className="font-medium">{agent.name}</div>
          <div className="text-xs text-muted-foreground">
            Status: <span className={statusTextColors[agent.status]}>{agent.status}</span>
          </div>
          {agent.task_description && (
            <div className="text-xs">{agent.task_description}</div>
          )}
          <div className="text-[10px] text-muted-foreground">
            Type: {agent.type} | Session: {agent.session || 'cmux'}
          </div>
        </div>
      </TooltipContent>
    </Tooltip>
  );
}
```

### 6c. Disable Direct Worker Interaction by Default

**Current State:**
- `WorkerConfirmModal` shows warning but still allows sending
- Confirmation is just a warning, not a blocker

**Proposed Enhancement:**

Add a user preference to completely disable worker messaging:

```typescript
// stores/settingsStore.ts (new)
export const useSettingsStore = create<SettingsState>()(
  persist(
    (set) => ({
      allowDirectWorkerMessages: false,
      setAllowDirectWorkerMessages: (allow: boolean) => set({ allowDirectWorkerMessages: allow }),
    }),
    { name: 'cmux-settings' }
  )
);

// ChatPanel.tsx - modify handleSend
const { allowDirectWorkerMessages } = useSettingsStore();

const handleSend = useCallback((message: string) => {
  if (isWorker && !allowDirectWorkerMessages) {
    // Show disabled state, not a confirmation
    toast.error('Direct worker messaging is disabled. Use supervisor instead.');
    return;
  }
  if (isWorker) {
    setPendingMessage(message);
    setShowWorkerConfirm(true);
  } else {
    handleSendDirect(message);
  }
}, [isWorker, allowDirectWorkerMessages, handleSendDirect]);
```

**Also add a toggle in the header:**

```typescript
// ChatHeader.tsx
{isWorker && (
  <div className="text-xs text-amber-500 flex items-center gap-2">
    <AlertTriangle className="h-3 w-3" />
    Worker - messaging via supervisor recommended
  </div>
)}
```

**Files to modify:**
- `src/frontend/src/components/chat/AgentActivityIndicator.tsx`
- `src/frontend/src/components/explorer/Explorer.tsx` (AgentItem)
- `src/frontend/src/stores/settingsStore.ts` (new)
- `src/frontend/src/components/chat/ChatPanel.tsx`
- `src/frontend/src/components/chat/ChatHeader.tsx`

---

## 7. Fix Scrolling/Auto-Scroll Behavior

### Current State
Recent commits (7572a07, c66f505) have improved scrolling:
- Unread count badge when scrolled up
- No forced auto-scroll
- Scroll-to-bottom button

### Remaining Issues

**Issue 1:** The `overflow-hidden` on parent containers can interfere with scroll detection.

**Current flow:**
```
ChatMessages (flex-1 flex flex-col relative overflow-hidden)
  └── ScrollArea (flex-1)
        └── Viewport (h-full w-full)
              └── Content div (p-4 space-y-4)
```

**Proposed fix:** Ensure clean flex hierarchy:

```typescript
// ChatMessages.tsx
return (
  <div className="flex-1 min-h-0 relative">  {/* min-h-0 is critical for flex scroll */}
    <ScrollArea className="h-full" viewportRef={viewportRef} onScroll={handleScroll}>
      <div className="p-4 space-y-4">
        {sortedMessages.map((message) => (
          <ChatMessage key={message.id} message={message} />
        ))}
        <div ref={bottomRef} />
      </div>
    </ScrollArea>

    {/* Floating button positioned relative to container, not ScrollArea */}
    {unreadCount > 0 && !isNearBottom && (
      <Button
        variant="secondary"
        size="icon"
        onClick={() => scrollToBottom(true)}
        className="absolute bottom-4 right-4 z-10 h-10 w-10 rounded-full shadow-lg"
      >
        <ArrowDown className="h-5 w-5" />
        <Badge variant="destructive" className="absolute -top-2 -right-2">
          {unreadCount > 99 ? '99+' : unreadCount}
        </Badge>
      </Button>
    )}
  </div>
);
```

**Issue 2:** Initial scroll position on agent switch may not be at bottom.

**Current logic:**
```typescript
if (isAgentSwitch) {
  requestAnimationFrame(() => scrollToBottom(false));
}
```

**Proposed improvement:** Use double RAF for more reliable rendering:

```typescript
if (isAgentSwitch) {
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      bottomRef.current?.scrollIntoView({ behavior: 'instant' });
    });
  });
}
```

**Files to modify:**
- `src/frontend/src/components/chat/ChatMessages.tsx`

---

## Implementation Priority

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| 1 | File tree unfold by default | 5 min | High UX |
| 2 | Scrolling fixes | 30 min | High UX |
| 3 | Agent tooltips | 20 min | Medium UX |
| 4 | Mailbox display cleanup | 45 min | Medium UX |
| 5 | Image display in viewer | 1 hr | Medium UX |
| 6 | Tool call expansion in chat | 30 min | Low UX |
| 7 | router.log cleanup | 15 min | Low |
| 8 | Mailbox archival script | 20 min | Low |
| 9 | Worker message blocking | 45 min | Low |

---

## Defense of Key Decisions

### Why keep router.log?
Debugging message routing is critical in a multi-agent system. The recent colon-parsing bug was found by analyzing router.log. Reducing verbosity (only log errors) provides the debugging benefit without the storage cost.

### Why not use a "read more" pattern for mailbox?
The mailbox is a system log, not user content. Users scanning it want to see the flow, not click into individual messages. Syntax highlighting serves this better than interactivity.

### Why simple shell rotation vs database archival?
CMUX's architecture uses shell scripts for orchestration (health.sh, router.sh). Adding a Python-based archival system would break the pattern. Shell rotation is consistent with the existing approach.

### Why block worker messages instead of just warning?
The warning modal is already present but doesn't prevent the action. For users who want the protection, a setting that actually blocks is more effective than a warning they can click through.

---

## Ready for Critic Review

I await the critic's assessment of this plan. Specific areas I'd welcome challenge on:
1. The mailbox rotation threshold (50KB / 1000 lines)
2. Whether to use `AgentTreeItem.tsx` (existing but unused) vs modifying `AgentItem`
3. The settings store approach for worker message blocking
4. Whether the scroll fixes are sufficient or need more investigation
