# Claude Code Project Instructions

## MCP Servers Available

You have access to the following MCP servers:

### context7
- **Purpose**: Library documentation and code context lookup
- **Usage**: Use to fetch documentation for any library/framework
- **Example**: Get docs for React, Express, Prisma, etc.

### browseruse
- **Purpose**: Web browser automation and research
- **Usage**: Navigate websites, research documentation, verify APIs
- **Example**: Look up API documentation, check package versions

## Workflow Instructions

When working on a feature in this project:

1. **Always read** `.multiclaude/FEATURE_SPEC.md` first if it exists
2. **Log status** to `.multiclaude/status.log` using format:
   ```
   $(date -Iseconds) [STATUS] Message
   ```
   Status codes: PENDING, IN_PROGRESS, BLOCKED, TESTING, COMPLETE, FAILED

3. **Log implementation details** to `.multiclaude/implementation.log`

4. **Use context7** to look up documentation for libraries before using them

5. **Use browseruse** for web research when needed

## Code Standards

- Follow existing code patterns in the project
- Write tests for all new functionality
- Do not modify files outside your feature boundary
- Update status log at each milestone
