# CMUX Dashboard Navigation & Layout UX Analysis

**Date:** 2026-01-31
**Analyst:** ux-nav-analysis worker
**Focus:** Discoverability, Visual Hierarchy, Information Architecture

---

## Executive Summary

The CMUX dashboard uses a three-panel layout with a left sidebar, central command center, and right activity panel. While functional, there are significant opportunities to improve navigation discoverability, visual hierarchy, and information architecture.

---

## Current Structure Analysis

### Layout Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ HEADER: cmux | main | multi-agent orchestrator | [Theme Toggle] │
├──────────────┬─────────────────────────────────┬────────────────┤
│   SIDEBAR    │        COMMAND CENTER           │   ACTIVITY     │
│              │                                 │                │
│ • AGENTS     │  "Command Center" heading       │  ACTIVITY      │
│   - list     │  Status badges                  │  50 events     │
│              │  Chat messages                  │  Event list    │
│ • MAILBOX    │  Input field                    │                │
│   - preview  │                                 │                │
│              │                                 │                │
│ • MEMORY     │                                 │                │
│   - file     │                                 │                │
│     tree     │                                 │                │
└──────────────┴─────────────────────────────────┴────────────────┘
```

### Panel Widths (observed)

- Left sidebar: ~17.7% (resizable, min 10%, max 25%)
- Center panel: ~42% (resizable)
- Right activity: ~40% (resizable, collapsible)

---

## Issues Identified

### 1. FILE TREE SUBDIRECTORY BUG (Critical)

**Observation:** Clicking on `attachments` or `artifacts` folders does not expand to show contents.

**Impact:** Users cannot browse files nested more than 2-3 levels deep, making the MEMORY section less useful.

**Current Behavior:**

- `journal > 2026-01-31 > attachments` - clicking shows nothing
- Files inside subdirectories are invisible

**Recommendation:** Implement recursive tree rendering (Note: worker-filetree-fix appears to have addressed this during analysis)

---

### 2. NAVIGATION DISCOVERABILITY

#### 2.1 Unclear Interactive Elements

**Issue:** Many clickable elements lack visual affordance.

| Element                        | Issue                                         |
| ------------------------------ | --------------------------------------------- |
| Agent buttons (SUP/WRK badges) | No hover state visible in snapshot            |
| File tree items                | Appear as plain text, not obviously clickable |
| "View Raw Mailbox" button      | Styled differently but purpose unclear        |
| Separator/resizer bars         | No visual indicator of draggability           |

**Recommendations:**

- Add subtle hover states to all interactive elements
- Use cursor changes (pointer, col-resize) more prominently
- Add subtle icons (folder, file) to file tree items

#### 2.2 Section Headers Not Obviously Collapsible

**Issue:** AGENTS, MAILBOX, MEMORY headers show `expandable expanded` state but lack clear expand/collapse icons.

**Recommendation:** Add chevron icons (▼/▶) to clearly indicate collapsibility.

---

### 3. VISUAL HIERARCHY ISSUES

#### 3.1 Agent List Lacks Status Differentiation

**Current:** All agents show as simple buttons with SUP/WRK badges.

**Missing Information:**

- Active vs idle status not color-coded
- No visual distinction between healthy, blocked, or failed agents
- Count badge shows total (7) but no breakdown

**Recommendation:**

- Color-code agent status: green (active), gray (idle), red (blocked/failed)
- Add status indicator dots next to agent names
- Show status breakdown in header: "AGENTS 7 (2 active, 1 blocked)"

#### 3.2 Mailbox Preview Lacks Hierarchy

**Current:** All messages shown with same styling regardless of type.

**Issues:**

- [DONE], [STATUS], [BLOCKED] prefixes in message text, not visually distinct
- No color coding for message types
- From/To information is small and de-emphasized

**Recommendation:**

- Color-code message types: green for DONE, blue for STATUS, red for BLOCKED
- Make from/to more prominent with avatar or colored badges
- Add timestamp grouping (Today, Yesterday, Older)

#### 3.3 Activity Panel Event Density

**Current:** 50 events in a flat list.

**Issues:**

- All events look identical
- No grouping by agent or time
- "Tool Call" events dominate without clear differentiation

**Recommendation:**

- Group events by agent with collapsible sections
- Show event type icons (tool, message, status)
- Add filtering by event type

---

### 4. INFORMATION ARCHITECTURE

#### 4.1 Command Center Header Confusion

**Current Header Elements:**

```
"Command Center" | WORKING | "Send tasks to the supervisor agent" | Connected | [dropdown]
```

**Issues:**

- "WORKING" status unclear - what is working?
- "Send tasks to the supervisor agent" - is this instruction or capability description?
- Dropdown button has no label

**Recommendation:**

- Rename to "Supervisor Chat" or "Task Assignment"
- Show currently selected agent prominently
- Replace status text with icon + tooltip
- Label the dropdown or use context menu pattern

#### 4.2 Memory Section Purpose Unclear

**Issue:** "MEMORY" section name doesn't communicate its purpose (journal/file storage).

**Recommendation:** Rename to "Files" or "Workspace" or show as tabs: "Journal | Artifacts | Logs"

#### 4.3 No Global Navigation

**Issue:** No way to navigate to:

- Settings/configuration
- Help/documentation
- System health overview
- Agent management (create/delete)

**Recommendation:** Add header navigation or settings gear icon

---

### 5. RESPONSIVE BEHAVIOR (to verify)

**Panel Resizers:** Vertical separators exist but behavior unclear:

- Separator 1: value="17.67" (sidebar width)
- Separator 2: value="59.61" (activity panel)

**Collapse behavior:** Activity panel has "Collapse" button, but sidebar and other sections lack quick collapse.

**Recommendation:**

- Add double-click to collapse/expand panels
- Add keyboard shortcuts for panel management
- Persist layout preferences in localStorage

---

## POSITIVE OBSERVATIONS

1. **Clear three-panel layout** - Standard pattern, easy to understand
2. **Real-time updates** - WebSocket connection shows "Connected" status
3. **Message threading** - Chat shows clear conversation flow with timestamps
4. **"Show more" truncation** - Long messages don't overwhelm the view
5. **Theme toggle** - Dark/light mode available (tested, works)
6. **Agent count in header** - Quick visibility of active agents

---

## PRIORITY RECOMMENDATIONS

### High Priority

1. ~~Fix file tree subdirectory expansion~~ (In progress by worker-filetree-fix)
2. Add visual status indicators to agent list
3. Color-code message types in mailbox preview

### Medium Priority

4. Add expand/collapse icons to section headers
5. Improve hover states on all interactive elements
6. Add filtering to activity panel

### Low Priority

7. Rename "MEMORY" section for clarity
8. Add global navigation/settings access
9. Implement keyboard shortcuts for navigation

---

## SCREENSHOTS CAPTURED

1. `ux-nav-main-view.png` - Initial dashboard state
2. `ux-nav-sidebar-state.png` - Sidebar with expanded sections
3. `ux-nav-dark-mode.png` - Dark theme activated

---

## APPENDIX: Element Inventory

### Sidebar Elements

| Element            | Type        | State                   |
| ------------------ | ----------- | ----------------------- |
| AGENTS header      | Button      | expandable, expanded    |
| Create new session | Button      | -                       |
| All Agents         | Button      | ALL badge               |
| supervisor         | Button      | SUP badge               |
| workers (7)        | Buttons     | WRK badges              |
| MAILBOX header     | Button      | expandable, expanded    |
| View Raw Mailbox   | Button      | -                       |
| Message previews   | Static text | 5 visible               |
| MEMORY header      | Button      | expandable, expanded    |
| Refresh            | Button      | -                       |
| File tree          | Buttons     | nested, some expandable |

### Command Center Elements

| Element        | Type      | Purpose                              |
| -------------- | --------- | ------------------------------------ |
| Heading        | h2        | "Command Center"                     |
| Status badge   | Static    | "WORKING"                            |
| Description    | Static    | "Send tasks to the supervisor agent" |
| Connection     | Static    | "Connected"                          |
| Agent selector | Button    | dropdown menu                        |
| Chat messages  | List      | scrollable                           |
| Input textbox  | Multiline | message composition                  |
| Send button    | Button    | disabled when empty                  |

### Activity Panel Elements

| Element         | Type    | Count                           |
| --------------- | ------- | ------------------------------- |
| Heading         | h2      | "ACTIVITY"                      |
| Event count     | Static  | "50 events"                     |
| Filter dropdown | Button  | haspopup menu                   |
| Collapse button | Button  | -                               |
| Event items     | Buttons | 50, expandable                  |
| Footer status   | Static  | "Connected, X agents, Y active" |

---

_Analysis complete. Findings should be synthesized with other UX workers for comprehensive recommendations._
