# UX Responsiveness Analysis - CMUX Dashboard

**Analyst:** ux-responsiveness-analysis
**Date:** 2026-01-31
**Method:** Code-based analysis (chrome-devtools browser in use by other worker)

## Executive Summary

The CMUX dashboard uses a hybrid responsive approach combining Tailwind CSS breakpoint classes with a custom `useIsMobile()` hook. The layout system is percentage-based with resizable panels. While generally well-structured, there are several hardcoded pixel values and potential small-viewport issues.

---

## Breakpoint System

### Primary Breakpoint
- **768px** - Mobile/desktop split via `useIsMobile()` hook
- Location: `src/frontend/src/hooks/use-mobile.tsx:3`

### Tailwind Breakpoints Used
| Breakpoint | Usage |
|------------|-------|
| `sm:` (640px) | Text visibility, button layout, sheet width |
| `md:` (768px) | Sidebar show/hide, input text size |

**Gap Identified:** No tablet-specific optimizations between `sm:` and `md:` breakpoints.

---

## Panel System Analysis

### Layout Structure (`ResizableLayout.tsx`)

| Panel | Min | Max | Default |
|-------|-----|-----|---------|
| Explorer (left) | 10% | 25% | 15% |
| Chat (center) | 30% | - | ~60% |
| Activity (right) | 15% (3% collapsed) | 40% | 25% |

**Concerns:**
1. No minimum pixel width - panels can become unusably narrow
2. No mobile layout fallback - 3-panel layout persists at all sizes
3. Activity panel collapse is percentage-based, not responsive to viewport

---

## Sidebar Responsive Behavior

### Widths
- Desktop: `16rem` (256px)
- Mobile: `18rem` (288px) - larger for touch targets
- Collapsed: `3rem` (48px)

### Mobile Adaptation
- Uses Sheet component (slide-in drawer) on mobile
- Hidden at `md:` breakpoint, shown as fixed sidebar
- Touch hit area expansion: `after:-inset-2` on mobile only

**Location:** `src/frontend/src/components/ui/sidebar.tsx:201-313`

---

## Hardcoded Pixel Values - Potential Issues

### High Risk (may cause overflow/clipping)

| Component | Value | File:Line | Issue |
|-----------|-------|-----------|-------|
| ChatInput | `max-h-[200px]` | ChatInput.tsx:66 | Fixed regardless of viewport |
| ChatInput | `min-h-[44px]` | ChatInput.tsx:66 | Acceptable (touch target) |
| CommandCenter textarea | `min-h-[80px]` | CommandCenter.tsx:108 | May be too tall on small screens |
| OutputPanel | `maxHeight: 400px` | OutputPanel.tsx:25 | Default may fill mobile viewport |
| StatusBar | `h-8` (32px) | StatusBar.tsx:15 | Fixed, consumes mobile space |

### Medium Risk (may need adjustment)

| Component | Value | File:Line | Issue |
|-----------|-------|-----------|-------|
| FileTree indent | `12px * level` | FileTree.tsx:57 | Deep nesting causes overflow |
| FileTree base padding | `8px + 18px` | FileTree.tsx:98 | Cumulative width on deep trees |
| Message bubble | `max-w-[80%]` | CommandCenter.tsx:151 | May be too wide on narrow screens |
| Activity icon | `w-12 h-12` | ActivityTimeline.tsx:74 | Fixed 48x48px |

### Low Risk (appropriate fixed values)

| Component | Value | File:Line |
|-----------|-------|-----------|
| Resize handle | `h-4 w-3` | resizable.tsx:36 |
| Rail width | `w-4` | sidebar.tsx:313 |

---

## Missing Responsive Features

### 1. No Mobile Layout Mode
The 3-panel horizontal layout is maintained at all sizes. On mobile:
- Panels become extremely narrow
- No stacked/tabbed view fallback
- Side panels should collapse to full-screen overlays

### 2. No Horizontal Overflow Handling
- File tree can overflow horizontally with deep nesting
- No `overflow-x-auto` on containers
- Long agent names may clip

### 3. No Minimum Viewport Support
- No handling for viewports < 320px
- Panel percentages become unusable below ~600px total width

### 4. Activity Panel Collapse
- Uses `writingMode: 'vertical-rl'` inline style (line 41)
- Not keyboard accessible in collapsed state
- No way to expand on mobile without mouse drag

---

## Responsive Classes Usage Summary

```
sm: classes  - 12 occurrences (text alignment, flex direction)
md: classes  - 15 occurrences (sidebar, text size, hit areas)
hidden/inline - 8 occurrences (content visibility toggles)
```

---

## Recommendations

### Critical (Mobile Usability)

1. **Add mobile layout mode** - Stack panels vertically or use tabs below 768px
2. **Make activity panel a drawer on mobile** - Similar to sidebar Sheet pattern
3. **Add viewport minimum** - Display warning or simplified UI below 480px

### Important (Better Experience)

4. **Cap file tree depth visually** - Truncate or wrap at 4+ levels
5. **Make OutputPanel height responsive** - Use `vh` units instead of fixed `400px`
6. **Add horizontal scroll to code/terminal views** - Prevent layout breaks

### Nice-to-Have (Polish)

7. **Add tablet breakpoint** - `lg:` (1024px) for 2-panel intermediate layout
8. **Make StatusBar collapsible** - Reclaim 32px on mobile
9. **Use CSS clamp() for dynamic sizing** - Replace hardcoded min/max values

---

## Files Analyzed

| File | Responsive Patterns |
|------|---------------------|
| `hooks/use-mobile.tsx` | Core breakpoint hook |
| `components/ui/sidebar.tsx` | Mobile drawer, CSS vars |
| `components/layout/ResizableLayout.tsx` | Panel percentages |
| `components/chat/ChatInput.tsx` | Dynamic height |
| `components/activity/ActivityTimeline.tsx` | Collapse behavior |
| `components/explorer/FileTree.tsx` | Indentation |
| `components/command/CommandCenter.tsx` | Fixed dimensions |
| `components/agents/OutputPanel.tsx` | Max height |
| `components/status/StatusBar.tsx` | Fixed position |

---

## Conclusion

The CMUX dashboard has a solid foundation for responsive design with Tailwind classes and a mobile detection hook. However, the **3-panel layout does not adapt to mobile viewports**, which is the primary usability gap. The hardcoded pixel values are mostly reasonable for desktop but may cause issues on mobile devices.

**Priority Fix:** Implement a mobile-first layout that stacks or tabs panels below 768px, similar to how the sidebar already converts to a Sheet component.
