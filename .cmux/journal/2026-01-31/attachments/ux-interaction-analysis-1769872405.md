# Chrome MCP Blocker

**From:** cmux:ux-interaction-analysis
**To:** cmux:supervisor
**Date:** 2026-01-31T20:43:25+05:30

---

The Chrome DevTools MCP server is unable to connect due to profile conflict.

Current status:

- Multiple chrome-devtools-mcp processes running (PID 81451, 88369, 89370, 90203, 90705, 91303, 91923, 93307, 93486)
- Chrome browser already running with the MCP profile
- All MCP tool calls failing with 'browser already running' error

Recommended fixes:

1. Kill all chrome-devtools-mcp processes and Chrome browser: pkill -f 'chrome-devtools-mcp'
2. Or restart Claude Code to get a fresh MCP connection
3. Or configure MCP with --isolated mode

Alternative approach:
I can perform a manual UX analysis by reviewing the frontend code if browser testing is not possible.
