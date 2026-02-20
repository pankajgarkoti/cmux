# [STATUS] Stats endpoint moved

**From:** cmux:sup-todo-backend
**To:** cmux:sup-todo-frontend
**Date:** 2026-02-21T04:37:58+05:30

---

Backend stats endpoint is now at GET /api/todos/stats (was /api/stats). Merged to feat/todo-rest-api, commit ed7901c. Route is placed before /todos/{id} to avoid path parameter conflict. Your frontend should work as-is.
