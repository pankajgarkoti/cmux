# CMUX Dashboard UX Improvement Plan - Combined Recommendations

**Date:** 2026-01-31
**Synthesized by:** ux-synthesizer
**Source Analyses:** ux-nav-analysis, ux-interaction-analysis, ux-chat-analysis, ux-responsiveness-analysis

---

## Executive Summary

Four parallel UX analyses examined the CMUX dashboard from different perspectives: navigation/layout, interaction patterns, chat interface, and responsive behavior. This document consolidates and prioritizes all findings into an actionable improvement plan.

**Overall Assessment:** The dashboard has a solid foundation with good component architecture (shadcn/ui, Zustand, React Query) but lacks mobile support, has accessibility gaps, and needs feedback improvements.

---

## Priority 1: CRITICAL FIXES (Blocking Usability)

These issues prevent users from accomplishing basic tasks or create significant barriers.

### 1.1 Mobile Layout Does Not Exist

**Sources:** responsiveness-analysis, nav-analysis
**Impact:** Dashboard unusable on mobile/tablet devices

**Problem:** The 3-panel layout persists at all screen sizes. Below ~768px, panels become unusably narrow with no fallback.

**Fix Required:**

- Add mobile layout mode that stacks panels vertically or uses tabs
- Convert Activity panel to Sheet/drawer on mobile (like existing Sidebar)
- Define minimum viewport (480px) with graceful degradation

**Files to modify:**

- `src/frontend/src/components/layout/ResizableLayout.tsx`
- `src/frontend/src/hooks/use-mobile.tsx`

**Effort:** High | **Impact:** Critical for mobile users

---

### 1.2 Keyboard Navigation Missing

**Sources:** interaction-analysis, chat-analysis
**Impact:** Application not usable without a mouse; accessibility barrier

**Problem:**

- File tree has no arrow key navigation
- Agent tree has no keyboard support
- No way to navigate without clicking

**Fix Required:**

- Add arrow key navigation to FileTree component
- Add arrow key navigation to agent list
- Add `aria-expanded`, `aria-controls` to all collapsibles
- Trap focus in modals

**Files to modify:**

- `src/frontend/src/components/explorer/FileTree.tsx`
- `src/frontend/src/components/explorer/AgentTreeItem.tsx`
- All modal components

**Effort:** Medium | **Impact:** Critical for accessibility

---

### 1.3 File Tree Subdirectory Expansion Bug

**Source:** nav-analysis
**Impact:** Cannot browse nested file structures

**Problem:** Clicking on `attachments` or `artifacts` folders does not expand contents. Files inside subdirectories are invisible.

**Status:** Reportedly in progress by worker-filetree-fix

**If not fixed:**

- Verify recursive rendering in FileTree component
- Check `fetchDirectoryContents` API returns nested items

**Files to check:** `src/frontend/src/components/explorer/FileTree.tsx`

**Effort:** Low (if bug) | **Impact:** Critical for file access

---

## Priority 2: HIGH (Significantly Improves Experience)

These issues significantly degrade the user experience but have workarounds.

### 2.1 Chat Auto-Scroll Behavior

**Source:** chat-analysis
**Impact:** Disruptive when reading older messages

**Problem:** Auto-scroll triggers on any new message with `behavior: 'instant'`, even when user is reading history. This is jarring and loses user's place.

**Fix Required:**

```typescript
// Only auto-scroll if user is near bottom
const isNearBottom = useRef(true);
// Use smooth scroll when auto-scrolling
behavior: "smooth";
```

**Files to modify:** `src/frontend/src/components/chat/ChatMessages.tsx`

**Effort:** Low | **Impact:** High for chat usability

---

### 2.2 Message Delivery Status Missing

**Sources:** chat-analysis
**Impact:** Users don't know if message was received

**Problem:** No visual feedback after sending a message. Users can't distinguish between "sending", "delivered", or "failed".

**Fix Required:**

- Add message states: `pending` → `sent` → `delivered` → `processing`
- Show status indicators (checkmarks, spinner, etc.)
- Keep failed messages in input with retry button

**Files to modify:**

- `src/frontend/src/components/chat/ChatMessage.tsx`
- `src/frontend/src/components/chat/ChatInput.tsx`
- Message API/store

**Effort:** Medium | **Impact:** High for user confidence

---

### 2.3 Error Messages Not Specific

**Sources:** chat-analysis, interaction-analysis
**Impact:** Users can't understand or fix problems

**Problem:** Generic "Failed to send message. Please try again." doesn't help users. Error messages appear in non-obvious locations.

**Fix Required:**

- Display specific API error messages
- Use toast notifications for errors (not inline)
- Add retry mechanism for failed operations

**Files to modify:**

- `src/frontend/src/components/chat/ChatPanel.tsx`
- Add toast notification system

**Effort:** Low | **Impact:** High for error recovery

---

### 2.4 Session Actions Hidden on Hover

**Sources:** interaction-analysis
**Impact:** Users don't discover available actions

**Problem:** Session dropdown actions (pause, terminate, etc.) only visible on hover. New users miss functionality entirely.

**Fix Required:**

- Show action buttons always (not just on hover)
- Use context menu pattern for less common actions
- Add tooltips for icon-only buttons

**Files to modify:** `src/frontend/src/components/explorer/Explorer.tsx`

**Effort:** Low | **Impact:** High for discoverability

---

### 2.5 Agent Status Not Visible

**Sources:** nav-analysis, interaction-analysis
**Impact:** Users can't see which agents are active/blocked

**Problem:**

- All agents look the same regardless of status
- No color coding (active, idle, blocked, failed)
- Count shows total but no breakdown

**Fix Required:**

- Color-code agent status dots: green (active), gray (idle), red (blocked), yellow (warning)
- Add status indicator patterns (not just color) for colorblind users
- Show breakdown: "AGENTS 7 (2 active, 1 blocked)"

**Files to modify:** `src/frontend/src/components/explorer/AgentTreeItem.tsx`

**Effort:** Low | **Impact:** High for monitoring

---

### 2.6 Keyboard Shortcuts Not Discoverable

**Sources:** chat-analysis, interaction-analysis
**Impact:** Power users don't know features exist

**Problem:** Shortcuts exist (Cmd+Enter, Cmd+K, Escape) but no UI shows them.

**Fix Required:**

- Add keyboard shortcuts help panel (Cmd+?)
- Show hints on first use
- Add more shortcuts: agent switching (Cmd+1/2/3)

**Files to modify:**

- `src/frontend/src/hooks/useChatKeyboard.ts`
- Create new KeyboardShortcutsHelp component

**Effort:** Medium | **Impact:** High for power users

---

### 2.7 Date Separators Missing in Chat

**Sources:** chat-analysis
**Impact:** Hard to understand conversation timeline

**Problem:** No visual indication of date boundaries in long conversations.

**Fix Required:**

- Add date separator headers ("Today", "Yesterday", "January 30")
- Group messages by date

**Files to modify:** `src/frontend/src/components/chat/ChatMessages.tsx`

**Effort:** Low | **Impact:** Medium

---

### 2.8 Touch Targets Too Small

**Sources:** interaction-analysis, chat-analysis
**Impact:** Difficult to use on touch devices

**Problem:** Some buttons (6x6, 24x24) are below the recommended 44x44px minimum for mobile.

**Fix Required:**

- Increase button minimum sizes to 44x44px on mobile
- Expand hit areas with invisible padding where visual size should stay small

**Files to modify:** Multiple component files

**Effort:** Medium | **Impact:** High for mobile

---

## Priority 3: NICE TO HAVE (Polish and Refinement)

These improvements enhance the experience but aren't essential.

### 3.1 Activity Feed Improvements

| Issue                          | Fix                                             |
| ------------------------------ | ----------------------------------------------- |
| Raw JSON display               | Format common types in human-readable summaries |
| 50 item hard limit             | Add "Load more" pagination                      |
| No search                      | Add text search/filter                          |
| Missing mailbox_message filter | Add to filter options                           |
| New items not highlighted      | Add subtle animation on arrival                 |

**Files:** `src/frontend/src/components/activity/ActivityTimeline.tsx`, `ActivityFilters.tsx`

---

### 3.2 Visual Hierarchy Enhancements

| Issue                                   | Fix                                              |
| --------------------------------------- | ------------------------------------------------ |
| Section headers not clearly collapsible | Add chevron icons (▼/▶)                          |
| Mailbox messages lack type colors       | Color-code: green=DONE, blue=STATUS, red=BLOCKED |
| Interactive elements lack affordance    | Add hover states, cursor changes                 |
| Collapsed panel uses rotated text       | Use icon-only collapsed state                    |

**Files:** Various sidebar and panel components

---

### 3.3 Chat Polish

| Issue                                          | Fix                                           |
| ---------------------------------------------- | --------------------------------------------- |
| No message draft persistence                   | Persist drafts to localStorage keyed by agent |
| Worker confirm modal has no "don't show again" | Add checkbox option                           |
| No message virtualization                      | Use react-window for long histories           |
| Messages re-sorted every render                | Memoize with useMemo                          |
| Collapse may break mid-word                    | Add word boundary fallback                    |
| Timestamp font too small (10px)                | Increase to 11-12px                           |

---

### 3.4 Navigation Clarity

| Issue                                 | Fix                              |
| ------------------------------------- | -------------------------------- |
| "MEMORY" section name unclear         | Rename to "Files" or "Workspace" |
| "Command Center" header confusing     | Rename to "Supervisor Chat"      |
| No global navigation (settings, help) | Add header nav or settings icon  |

---

### 3.5 Responsiveness Polish

| Issue                            | Fix                            |
| -------------------------------- | ------------------------------ |
| No tablet-specific breakpoint    | Add 1024px intermediate layout |
| Fixed OutputPanel height (400px) | Use vh units                   |
| Deep file tree causes overflow   | Cap visual depth, add scroll   |
| StatusBar consumes mobile space  | Make collapsible               |

---

### 3.6 Accessibility Polish

| Issue                                    | Fix                        |
| ---------------------------------------- | -------------------------- |
| Animations ignore prefers-reduced-motion | Add media query check      |
| Status changes not announced             | Add ARIA live regions      |
| Some focus rings not visible             | Audit focus-visible states |
| Icon buttons lack aria-label             | Add labels to all          |

---

## Implementation Roadmap

### Phase 1: Critical (Week 1)

1. Mobile layout mode (stacked panels + drawers)
2. Keyboard navigation for trees
3. Verify file tree expansion fix

### Phase 2: High Priority (Week 2)

1. Auto-scroll behavior fix
2. Message delivery status
3. Toast error notifications
4. Session actions visibility
5. Agent status colors

### Phase 3: Discovery & Shortcuts (Week 3)

1. Keyboard shortcuts help panel
2. Date separators
3. Touch target sizes
4. Section collapse chevrons

### Phase 4: Polish (Ongoing)

1. Activity feed improvements
2. Visual hierarchy tweaks
3. Performance optimizations
4. Accessibility audit completion

---

## Quick Wins (Low Effort, High Value)

These can be done in a few lines of code:

1. **Auto-scroll fix** - Add `isNearBottom` check before scrolling
2. **Memoize sorted messages** - Wrap in `useMemo`
3. **Add chevrons to collapsibles** - Simple icon addition
4. **Show session actions always** - Remove `group-hover` condition
5. **Increase timestamp size** - Change `text-[10px]` to `text-xs`

---

## Files Most Frequently Cited

| File                   | Citation Count | Primary Issues                     |
| ---------------------- | -------------- | ---------------------------------- |
| `ChatMessages.tsx`     | 4              | Auto-scroll, dates, virtualization |
| `ChatInput.tsx`        | 3              | Touch targets, drafts, hints       |
| `FileTree.tsx`         | 3              | Expansion bug, keyboard nav, depth |
| `AgentTreeItem.tsx`    | 3              | Status colors, keyboard nav        |
| `ResizableLayout.tsx`  | 3              | Mobile layout, panel sizing        |
| `ActivityTimeline.tsx` | 3              | Pagination, search, formatting     |

---

## Conclusion

The CMUX dashboard needs **mobile support** as the most critical improvement. Beyond that, focus on **feedback loops** (delivery status, specific errors) and **discoverability** (keyboard shortcuts, visible actions). The foundation is solid - these improvements build on existing patterns rather than requiring rewrites.

**Recommended First Action:** Implement mobile layout mode using the existing Sheet component pattern from the sidebar.

---

_Synthesized from analyses by: ux-nav-analysis, ux-interaction-analysis, ux-chat-analysis, ux-responsiveness-analysis_
