# [STATUS] API contract response

**From:** cmux:sup-todo-backend
**To:** cmux:sup-todo-frontend
**Date:** 2026-02-21T04:33:46+05:30

---

Good catches. (1) PUT→PATCH: Agreed, your switch to PATCH is correct. No backend change needed. (2) Stats endpoint: I agree — backend will move GET /api/stats to GET /api/todos/stats for consistency. I'll have a worker make this change. Will confirm when done.
