# UI/UX Final Implementation Plan

**Status:** AGREED (Defender + Critic)
**Date:** 2026-02-01
**Debate Rounds:** 2

---

## Executive Summary

This plan implements 7 UI/UX improvements for the CMUX dashboard. All changes have been debated and agreed upon by defender and critic agents. The plan is technically sound, appropriately scoped, and ready for implementation.

---

## Implementation Tasks

### Task 1: File Tree State Persistence

**Goal:** Remember which folders are expanded/collapsed across page refreshes.

**Files to modify:**
- `src/frontend/src/components/explorer/FileTree.tsx`

**Implementation:**

```typescript
// Add persistence hook
function getDefaultOpenPaths(items: FileTreeItem[], maxDepth = 2, currentDepth = 0): string[] {
  if (currentDepth >= maxDepth) return [];
  return items
    .filter(i => i.type === 'directory')
    .flatMap(i => [i.path, ...getDefaultOpenPaths(i.children || [], maxDepth, currentDepth + 1)]);
}

// In FileTree component, replace local state:
interface FileTreeProps {
  items: FileTreeItem[];
  onFileSelect?: (item: FileTreeItem) => void;
  selectedPath?: string;
}

export function FileTree({ items, onFileSelect, selectedPath }: FileTreeProps) {
  const [openPaths, setOpenPaths] = useState<Set<string>>(() => {
    const stored = localStorage.getItem('cmux-filetree-open');
    if (stored) {
      try { return new Set(JSON.parse(stored)); }
      catch { /* ignore */ }
    }
    return new Set(getDefaultOpenPaths(items));
  });

  useEffect(() => {
    localStorage.setItem('cmux-filetree-open', JSON.stringify([...openPaths]));
  }, [openPaths]);

  const togglePath = (path: string) => {
    setOpenPaths(prev => {
      const next = new Set(prev);
      if (next.has(path)) next.delete(path);
      else next.add(path);
      return next;
    });
  };

  return (
    <div className="space-y-0.5">
      {items.map((item) => (
        <FileTreeNode
          key={item.path}
          item={item}
          onFileSelect={onFileSelect}
          selectedPath={selectedPath}
          level={0}
          openPaths={openPaths}
          togglePath={togglePath}
        />
      ))}
    </div>
  );
}

// Update FileTreeNode to use openPaths prop instead of local state
interface FileTreeNodeProps {
  item: FileTreeItem;
  onFileSelect?: (item: FileTreeItem) => void;
  selectedPath?: string;
  level: number;
  openPaths: Set<string>;
  togglePath: (path: string) => void;
}

function FileTreeNode({ item, onFileSelect, selectedPath, level, openPaths, togglePath }: FileTreeNodeProps) {
  const isOpen = openPaths.has(item.path);
  // ... rest of component uses isOpen and togglePath(item.path) instead of local state
}
```

**Testing:** Expand/collapse folders, refresh page, verify state persists.

---

### Task 2: Agent Tooltips with AgentTreeItem

**Goal:** Show agent details on hover in sidebar. Consolidate duplicate code.

**Files to modify:**
- `src/frontend/src/components/explorer/AgentTreeItem.tsx`
- `src/frontend/src/components/explorer/Explorer.tsx`

**Implementation:**

```typescript
// AgentTreeItem.tsx - Add tooltip
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';

export function AgentTreeItem({ agent, isSelected, onClick }: AgentTreeItemProps) {
  const isSupervisor = agent.type === 'supervisor';
  const { latestEventBySession, isAgentActive } = useAgentEventStore();
  // ... existing isWorking logic ...

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <button
          onClick={onClick}
          className={cn(/* existing classes */)}
        >
          {/* existing button content */}
        </button>
      </TooltipTrigger>
      <TooltipContent side="right" className="max-w-xs">
        <div className="space-y-1">
          <div className="font-medium">{agent.name}</div>
          <div className="text-xs">
            Status: <span className={cn(
              agent.status === 'COMPLETE' && 'text-green-400',
              agent.status === 'BLOCKED' && 'text-red-400',
              agent.status === 'IN_PROGRESS' && 'text-blue-400'
            )}>{agent.status}</span>
          </div>
          {agent.task_description && (
            <div className="text-xs text-muted-foreground">{agent.task_description}</div>
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

```typescript
// Explorer.tsx - Replace AgentItem with AgentTreeItem
import { AgentTreeItem } from './AgentTreeItem';

// Remove the local AgentItem function (lines ~558-599)

// In SessionAgentGroup, replace:
{group.agents.map((agent) => (
  <AgentTreeItem
    key={agent.id}
    agent={agent}
    isSelected={selectedAgentId === agent.id}
    onClick={() => onSelectAgent(agent.id)}
  />
))}
```

**Testing:** Hover over agents in sidebar, verify tooltip shows status and details.

---

### Task 3: Mailbox Viewer with Syntax Highlighting

**Goal:** Display mailbox file with color-coded message types.

**Files to modify:**
- `src/frontend/src/components/explorer/MemoryViewer.tsx`
- `src/frontend/src/components/explorer/Explorer.tsx` (MailboxSection)

**Implementation:**

```typescript
// MemoryViewer.tsx - Add MailboxViewer
const isMailbox = file.name === 'mailbox';

// In render, before other type checks:
if (isMailbox) {
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="px-4 py-3 border-b bg-muted/30 flex items-center gap-2 flex-shrink-0">
        <FileText className="h-4 w-4 text-muted-foreground flex-shrink-0" />
        <span className="text-sm font-medium">Mailbox</span>
      </div>
      <ScrollArea className="flex-1">
        <MailboxViewer content={content || ''} />
      </ScrollArea>
    </div>
  );
}

function MailboxViewer({ content }: { content: string }) {
  if (!content.trim()) {
    return <p className="p-3 text-sm text-muted-foreground">No messages</p>;
  }

  const getStatusColor = (subject: string) => {
    if (subject.includes('[DONE]')) return 'text-green-400';
    if (subject.includes('[BLOCKED]')) return 'text-red-400';
    if (subject.includes('[STATUS]')) return 'text-blue-400';
    if (subject.includes('[QUESTION]')) return 'text-yellow-400';
    return 'text-foreground';
  };

  const lines = content.split('\n').filter(Boolean);

  return (
    <div className="font-mono text-xs space-y-1 p-3">
      {lines.map((line, i) => {
        // Match: [timestamp] from -> to: subject
        const match = line.match(/^\[([^\]]+)\] ([^\s]+) -> ([^\s]+): (.+)$/);
        if (!match) {
          return <div key={i} className="text-muted-foreground">{line}</div>;
        }

        const [, timestamp, from, to, subject] = match;
        const time = timestamp.split('T')[1]?.slice(0, 8) || timestamp;
        const fromAgent = from.split(':').pop() || from;
        const toAgent = to.split(':').pop() || to;

        return (
          <div key={i} className="flex gap-2 items-start hover:bg-muted/50 rounded px-1">
            <span className="text-muted-foreground shrink-0">[{time}]</span>
            <span className="text-blue-400 shrink-0">{fromAgent}</span>
            <span className="text-muted-foreground">→</span>
            <span className="text-green-400 shrink-0">{toAgent}</span>
            <span className={cn("truncate", getStatusColor(subject))}>{subject}</span>
          </div>
        );
      })}
    </div>
  );
}
```

```typescript
// Explorer.tsx - Simplify MailboxSection (remove clickable message items)
// Keep only the "View Raw Mailbox" button and a simple status line
<CollapsibleContent className="mt-1">
  {isLoading ? (
    <Skeleton className="h-4 w-full mx-3" />
  ) : (
    <>
      <div className="px-3 py-1 text-xs text-muted-foreground">
        {messageCount > 0 ? `${messageCount} recent messages` : 'No recent messages'}
      </div>
      {mailboxItem && (
        <button
          onClick={() => handleFileSelect(mailboxItem)}
          className={cn(
            'w-full flex items-center gap-2 px-3 py-1.5 text-sm rounded-md transition-colors text-left',
            'hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
            selectedFile?.path === mailboxItem.path && 'bg-sidebar-accent text-sidebar-accent-foreground'
          )}
        >
          <Inbox className="h-4 w-4 text-blue-500 flex-shrink-0" />
          <span className="truncate">View Mailbox</span>
        </button>
      )}
    </>
  )}
</CollapsibleContent>
```

**Testing:** Click "View Mailbox", verify syntax highlighting and color coding.

---

### Task 4: Image Display in MemoryViewer

**Goal:** Display PNG, JPG, GIF, WebP images inline.

**Files to modify:**
- `src/frontend/src/components/explorer/MemoryViewer.tsx`
- `src/server/routes/filesystem.py`
- `pyproject.toml` (add python-magic)

**Backend Implementation:**

```python
# src/server/routes/filesystem.py
import magic
from fastapi.responses import FileResponse

SAFE_IMAGE_MIMES = {'image/png', 'image/jpeg', 'image/gif', 'image/webp'}
MAX_IMAGE_SIZE = 5 * 1024 * 1024  # 5MB

@router.get("/content")
async def get_file_content(path: str, raw: bool = False):
    # ... existing path validation ...

    if raw:
        # Size check
        file_size = full_path.stat().st_size
        if file_size > MAX_IMAGE_SIZE:
            raise HTTPException(400, "File too large for inline display (max 5MB)")

        # MIME validation
        mime = magic.from_file(str(full_path), mime=True)
        if mime not in SAFE_IMAGE_MIMES:
            raise HTTPException(400, f"Unsupported file type: {mime}")

        return FileResponse(
            full_path,
            media_type=mime,
            headers={"Cache-Control": "public, max-age=3600"}
        )

    # ... existing text content logic ...
```

```toml
# pyproject.toml - Add dependency
[project]
dependencies = [
    # ... existing deps ...
    "python-magic>=0.4.27",
]
```

**Frontend Implementation:**

```typescript
// MemoryViewer.tsx
import { API_BASE } from '@/lib/constants';

// Add image detection (no SVG for security)
const isImage = /\.(png|jpg|jpeg|gif|webp)$/i.test(file.name);

// In render, before other type checks:
if (isImage) {
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="px-4 py-3 border-b bg-muted/30 flex items-center gap-2 flex-shrink-0">
        <FileText className="h-4 w-4 text-muted-foreground flex-shrink-0" />
        <span className="text-sm font-medium truncate">{file.name}</span>
      </div>
      <div className="flex-1 flex items-center justify-center p-4 bg-muted/10">
        <img
          src={`${API_BASE}/api/filesystem/content?path=${encodeURIComponent(file.path)}&raw=true`}
          alt={file.name}
          className="max-w-full max-h-full object-contain rounded-lg shadow-sm"
          onError={(e) => {
            e.currentTarget.style.display = 'none';
            e.currentTarget.parentElement!.innerHTML =
              '<p class="text-sm text-muted-foreground">Failed to load image</p>';
          }}
        />
      </div>
    </div>
  );
}
```

**Testing:** Add a PNG to `.cmux/journal/*/attachments/`, click it, verify display.

---

### Task 5: Disable Worker Input (Simplified)

**Goal:** Prevent direct messaging to workers, show explanation instead.

**Files to modify:**
- `src/frontend/src/components/chat/ChatPanel.tsx`
- `src/frontend/src/components/chat/WorkerConfirmModal.tsx` (DELETE)

**Implementation:**

```typescript
// ChatPanel.tsx
import { AlertTriangle } from 'lucide-react';

// Remove WorkerConfirmModal import and state

// Replace the input section:
{isWorker ? (
  <div className="px-4 py-3 border-t bg-muted/30 flex items-center gap-2 text-sm text-muted-foreground">
    <AlertTriangle className="h-4 w-4 text-amber-500 flex-shrink-0" />
    <span>Workers receive tasks from supervisor. Select supervisor to send messages.</span>
  </div>
) : (
  <>
    <ChatInput
      onSend={handleSend}
      isPending={sendMutation.isPending}
      placeholder={`Message ${targetAgent}...`}
      inputRef={inputRef}
    />
    {sendMutation.isError && (
      <p className="px-4 pb-2 text-sm text-destructive">
        Failed to send message. Please try again.
      </p>
    )}
  </>
)}

// Remove WorkerConfirmModal from render
```

```bash
# Delete dead code
rm src/frontend/src/components/chat/WorkerConfirmModal.tsx
```

**Testing:** Select a worker agent, verify input is replaced with message.

---

### Task 6: Tool Call Truncation in Activity Indicator

**Goal:** Prevent UI crash from large tool inputs.

**Files to modify:**
- `src/frontend/src/components/chat/AgentActivityIndicator.tsx`

**Implementation:**

```typescript
// AgentActivityIndicator.tsx
import { useState } from 'react';
import { ChevronDown } from 'lucide-react';

export function AgentActivityIndicator({ agentId, className }: AgentActivityIndicatorProps) {
  const [showDetails, setShowDetails] = useState(false);
  // ... existing logic ...

  if (!isVisible) return null;

  const toolName = latestActiveEvent?.tool_name || 'Working';
  const description = getToolDescription(toolName);

  // Truncate tool input for display
  const inputPreview = (() => {
    if (!latestActiveEvent?.tool_input) return null;
    const str = JSON.stringify(latestActiveEvent.tool_input, null, 2);
    if (str.length > 500) return str.slice(0, 500) + '\n... (truncated)';
    return str;
  })();

  return (
    <div className={cn('border-t bg-muted/30', className)}>
      <button
        onClick={() => setShowDetails(!showDetails)}
        className="w-full flex items-center gap-2 px-4 py-2 text-sm text-muted-foreground hover:bg-muted/50 transition-colors"
      >
        <Loader2 className="h-4 w-4 animate-spin text-primary" />
        <span className="font-medium text-foreground/80">{description}</span>
        {inputPreview && (
          <ChevronDown className={cn(
            'h-4 w-4 ml-auto transition-transform',
            showDetails && 'rotate-180'
          )} />
        )}
      </button>

      {showDetails && inputPreview && (
        <div className="px-4 pb-2">
          <pre className="text-[10px] font-mono bg-muted/50 rounded p-2 max-h-32 overflow-auto whitespace-pre-wrap">
            {inputPreview}
          </pre>
        </div>
      )}
    </div>
  );
}
```

**Testing:** Trigger a Read tool on a large file, verify truncation.

---

### Task 7: Mailbox Daily Rotation

**Goal:** Prevent mailbox from growing indefinitely.

**Files to create/modify:**
- `src/orchestrator/lib/mailbox_rotate.sh` (NEW)
- `src/orchestrator/health.sh`

**Implementation:**

```bash
# src/orchestrator/lib/mailbox_rotate.sh
#!/usr/bin/env bash
# Daily mailbox rotation with locking

rotate_mailbox() {
    local mailbox="${CMUX_MAILBOX:-.cmux/mailbox}"
    local lockfile="/tmp/cmux_mailbox.lock"
    local rotation_marker=".cmux/.last_mailbox_rotation"

    # Check if already rotated today
    local today=$(date +%Y-%m-%d)
    if [[ -f "$rotation_marker" ]] && [[ "$(cat "$rotation_marker" 2>/dev/null)" == "$today" ]]; then
        return 0
    fi

    # Non-blocking lock
    (
        flock -n 200 || { echo "Rotation skipped (locked)"; exit 0; }

        # Only rotate if mailbox has content
        if [[ -s "$mailbox" ]]; then
            local archive_dir=".cmux/journal/$today/archives"
            mkdir -p "$archive_dir"
            mv "$mailbox" "$archive_dir/mailbox-$(date +%H%M%S).bak"
            touch "$mailbox"
            echo "0" > .cmux/.router_line
            echo "Mailbox rotated to $archive_dir"
        fi

        echo "$today" > "$rotation_marker"
    ) 200>"$lockfile"
}
```

```bash
# src/orchestrator/health.sh - Add rotation call
source "${SCRIPT_DIR}/lib/mailbox_rotate.sh"

# In the health check loop, after existing checks:
rotate_mailbox
```

**Testing:** Create 100+ line mailbox, run health.sh, verify rotation.

---

### Task 8: router.log Daily Rotation

**Goal:** Prevent router.log from growing indefinitely.

**Files to modify:**
- `src/orchestrator/health.sh`

**Implementation:**

```bash
# Add to health.sh

rotate_router_log() {
    local log="${CMUX_ROUTER_LOG:-.cmux/router.log}"
    local rotation_marker=".cmux/.last_routerlog_rotation"

    local today=$(date +%Y-%m-%d)
    if [[ -f "$rotation_marker" ]] && [[ "$(cat "$rotation_marker" 2>/dev/null)" == "$today" ]]; then
        return 0
    fi

    if [[ -s "$log" ]]; then
        local archive_dir=".cmux/journal/$today/archives"
        mkdir -p "$archive_dir"
        mv "$log" "$archive_dir/router-$(date +%H%M%S).log"
        touch "$log"
        echo "Router log rotated"
    fi

    echo "$today" > "$rotation_marker"
}

# Call in health check loop
rotate_router_log
```

**Testing:** Run health.sh, verify log rotation occurs once per day.

---

### Task 9: Scroll Behavior (VERIFY FIRST)

**Goal:** Ensure scroll-to-bottom works on agent switch.

**Pre-Implementation:**
1. Open dashboard, select an agent with many messages
2. Switch to another agent
3. Verify scroll position is at bottom
4. If it works (after commit 7572a07), no changes needed

**If issue found, implement:**

```typescript
// ChatMessages.tsx - Double RAF for reliable scroll
if (isAgentSwitch) {
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      bottomRef.current?.scrollIntoView({ behavior: 'instant' });
    });
  });
}
```

---

## Implementation Order

To avoid merge conflicts, implement in this sequence:

1. **Backend first:** Task 4 (filesystem.py + pyproject.toml)
2. **Orchestration:** Tasks 7, 8 (shell scripts)
3. **Frontend - Explorer:** Tasks 1, 2 (FileTree.tsx, AgentTreeItem.tsx, Explorer.tsx)
4. **Frontend - MemoryViewer:** Tasks 3, 4 frontend (MemoryViewer.tsx)
5. **Frontend - Chat:** Tasks 5, 6 (ChatPanel.tsx, AgentActivityIndicator.tsx)
6. **Verification:** Task 9 (test only, implement if needed)

---

## Testing Checklist

| Task | Test Method | Expected Result |
|------|-------------|-----------------|
| 1 | Expand folder, refresh | Folder still expanded |
| 2 | Hover agent | Tooltip shows status/task |
| 3 | Click mailbox | Color-coded messages |
| 4 | Click PNG file | Image displayed |
| 5 | Select worker | Input hidden, message shown |
| 6 | Large tool call | Input truncated to 500 chars |
| 7 | Wait for health check | Mailbox archived daily |
| 8 | Wait for health check | router.log archived daily |
| 9 | Switch agents | Scroll at bottom |

---

## Files Changed Summary

| File | Tasks | Action |
|------|-------|--------|
| `src/frontend/src/components/explorer/FileTree.tsx` | 1 | Modify |
| `src/frontend/src/components/explorer/AgentTreeItem.tsx` | 2 | Modify |
| `src/frontend/src/components/explorer/Explorer.tsx` | 2, 3 | Modify |
| `src/frontend/src/components/explorer/MemoryViewer.tsx` | 3, 4 | Modify |
| `src/frontend/src/components/chat/ChatPanel.tsx` | 5 | Modify |
| `src/frontend/src/components/chat/WorkerConfirmModal.tsx` | 5 | DELETE |
| `src/frontend/src/components/chat/AgentActivityIndicator.tsx` | 6 | Modify |
| `src/server/routes/filesystem.py` | 4 | Modify |
| `pyproject.toml` | 4 | Modify |
| `src/orchestrator/lib/mailbox_rotate.sh` | 7 | CREATE |
| `src/orchestrator/health.sh` | 7, 8 | Modify |

---

## Out of Scope (Deferred)

- Mobile/responsive layout
- Accessibility audit
- PDF display
- Archive retention policy
- Expand/collapse all buttons

---

**Plan Status: FINAL - Ready for Implementation**
