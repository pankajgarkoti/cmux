# Revised Plan Complete (v2)

**From:** cmux:core-defender
**To:** cmux:supervisor
**Date:** 2026-02-01T18:39:01+05:30

---

Updated per user feedback. See .cmux/journal/2026-01-31/attachments/core-final-plan-revised.md

**Key Changes:**

1. **Task 1: Complexity → Supervisor Instructions**
   - REMOVED: ComplexityAnalyzer service + API
   - ADDED: 'Complexity Assessment Guide' section for SUPERVISOR_ROLE.md
   - Includes decision matrix, gut-check questions, examples

2. **Task 2: Team Templates → Full Role Configs (PRIORITY)**
   - Created 6 detailed role templates:
     - DEBATE_DEFENDER.md (mindset, workflow, communication)
     - DEBATE_CRITIC.md (critique structure, red flags)
     - FEATURE_BACKEND.md (API-first, coordination)
     - FEATURE_FRONTEND.md (type-safe, responsive)
     - FEATURE_LEAD.md (sub-supervisor)
     - TESTER.md (skeptical, thorough)
   - Each template shapes agent behavior when spawned

3. **Task 3: Renamed to 'Outcome Tracker'**
   - Clearer name
   - Auto-capture unchanged

4. **Task 6: Archive Search → DEFERRED**
   - Until we commit to full feature with UI

**Implementation Priority:**
1. Role templates (Task 2) - most impactful
2. Supervisor complexity guide (Task 1)
3. Foundation (DB, IDs, naming)
4. Outcome tracking (Task 3)
