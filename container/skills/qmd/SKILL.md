---
name: qmd
description: Search past conversations and documentation. Use when users ask about things mentioned before, past discussions, or need context from history.
allowed-tools: Grep, Glob, Read
---

# QMD - Conversation Search

Search past conversations and documentation via the QMD MCP server.

## MCP Tools (Preferred)

QMD runs as an HTTP MCP server on a centralized host (for example, a
homelab inference box shared across multiple agents). The URL is
configured per-agent via `QMD_MCP_URL` in the host `.env`;
`container-runner.ts` forwards it into the container, and the
agent-runner registers it as an MCP server at session start. If
`QMD_MCP_URL` is unset, the qmd MCP server is not registered at all and
only the grep fallback below is available.

Available tools:
- `mcp__qmd__query` - Hybrid search (lex + vec + rerank, best quality)
- `mcp__qmd__get` - Retrieve a document by path or docid
- `mcp__qmd__multi_get` - Batch retrieve by glob pattern
- `mcp__qmd__status` - Check index health and list collections

### Discovering collections

Do not hardcode a collection name. Call `mcp__qmd__status` first to see
which collections are available on the configured qmd instance, then pass
one or more of those names as the `collections` field in your query.

Centralized deployments typically have one collection per agent (for
example `capn`, `miniclaw`, `sage`). Host-local deployments may have a
single collection named after the active group. Let `status` tell you.

### Example query

```json
{
  "searches": [
    { "type": "lex", "query": "search term" },
    { "type": "vec", "query": "natural language question" }
  ],
  "collections": ["<collection-name-from-status>"],
  "limit": 10
}
```

## Fallback: Direct File Search

If the QMD MCP server is unreachable, fall back to grepping the
conversation files that are mounted into the container:

```bash
# Find conversations containing a term
grep -r "term" /workspace/group/conversations/

# List recent conversations
ls -lt /workspace/group/conversations/ | head -10
```

Note: this only searches the current group's local conversations, not
the centralized index across all agents.

## Conversation Files Location

- Conversations: `/workspace/group/conversations/*.md`
- Documentation: `/workspace/group/docs/*.md`
- Group memory: `/workspace/group/CLAUDE.md`

## When to Use

- User asks "what did we discuss about X"
- User mentions something from a past conversation
- Need context from previous sessions
- Looking up decisions or preferences mentioned before
