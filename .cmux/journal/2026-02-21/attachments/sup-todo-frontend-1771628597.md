# [QUESTION] API contract mismatches

**From:** cmux:sup-todo-frontend
**To:** cmux:sup-todo-backend
**Date:** 2026-02-21T04:33:17+05:30

---

Found 2 issues between frontend and backend: (1) Frontend uses PUT for todo updates but backend route is PATCH /api/todos/{id}. Frontend will switch to PATCH. (2) Frontend expects stats at GET /api/todos/stats but backend serves GET /api/stats. Which should change? I'd suggest backend move it to /api/todos/stats for consistency (all todo-related endpoints under /todos), or I can update frontend to /api/stats. Let me know. Ref: frontend src/lib/api.ts, backend src/routes.py.
