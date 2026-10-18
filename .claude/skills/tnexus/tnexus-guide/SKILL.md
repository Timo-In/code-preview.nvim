---
name: tnexus-guide
description: "Use when you need to understand the architecture, database schema, indexed file coverage, or CLI capabilities of the Tnexus code graph."
---

# Tnexus CLI Architecture and Schema Guide

## When to Use

- When first loading the repository to understand what metadata and graph indexes are available.
- When you want to check the indexed scope, branch/runtime state, or overall graph readiness of the codebase.
- When you want to check how many nodes and edges are indexed.

## Workflow

```
1. rtk tnexus status
2. rtk tnexus files --filter "src/"
3. rtk tnexus context "summarize the architecture of this repository" --format markdown
```

## `tnexus files` Usage Boundary

- **`rtk tnexus files` shows the indexed file set** for the current graph. It is not a filesystem crawler.
- **`--pattern` uses a full-path glob** relative to the project root, not fuzzy filename matching.
- Prefer examples such as:
  - `rtk tnexus files --pattern '**/*.vue'`
  - `rtk tnexus files --pattern '**/dashboard.vue'`
  - `rtk tnexus files --filter 'admin_vue/src/'`
- Common mistake:
  - `rtk tnexus files --pattern 'dashboard.vue'` usually misses nested files because it only matches a root-level path.
- Use it to:
  - Verify which directories or file types are indexed.
  - Confirm coverage before deeper `context`, `query`, `cypher`, or `affected` work.
  - Check whether `sync` picked up the paths you expect.
- Do not use it for:
  - Fuzzy filename lookup.
  - File-content search.
  - Regex or contains-style path filtering.
- Routing rule:
  - If the goal is file/path lookup, prefer `rtk rg --files | rtk rg '...'`.
  - If the goal is symbol lookup or semantic analysis, prefer the dedicated analysis CLI first: `rtk tnexus query`, `context`, `callers`, `callees`, `impact`, `node`, and `read`.
  - Use `rtk rg '...'` for raw file-content search, or only as a fallback when Tnexus cannot answer a symbol question.

## Core Schema and Entities

The code graph maps all semantic components (functions, structs, traits, methods, classes) into a local `SQLite` database. Key tables you can reason about after inspecting `rtk tnexus status` and, when necessary, query through `rtk tnexus cypher` or direct SQLite access:

1. **`nodes`**: The code symbols.
   - `id`: Unique content-hash ID of the symbol.
   - `kind`: The symbol type (`function`, `method`, `struct`, `class`, `interface`, `trait`, `impl`).
   - `name`: Short name.
   - `qualified_name`: Fully qualified name (e.g., `crate::graph::LeidenClusterer`).
   - `file_path`: Project-relative file path.
   - `start_line`, `end_line`: 1-based source coordinates.

2. **`edges`**: Relationships between symbols.
   - `source`, `target`: Node IDs.
   - `kind`: The relationship type (`calls`, `uses`, `implements`, `extends`, `contains`).

3. **`files`**: Scanned and indexed files.
   - `path`, `content_hash`, `size`, `node_count`.

## CLI-First Inspection Strategy

Use the following progression before reading the raw database:

```bash
rtk tnexus status --details
rtk tnexus files --pattern '**/*.rs'
rtk tnexus context "summarize the main modules and their relationships" --format markdown
```

- **`rtk tnexus status --details`**: Inspect counts, freshness, and node-kind distribution.
- **`rtk tnexus files`**: Verify which directories and file types are actually indexed, or narrow the indexed boundary before deeper graph queries.
- **`rtk tnexus context`**: Ask for an architecture summary in natural language, backed by the graph.
- **`rtk tnexus node` / `rtk tnexus read`**: Pivot from the summary to exact node metadata or file structure without leaving the CLI.
- **`rtk tnexus cypher`**: Use for exact structural questions that need graph edges, not prose.

## Risk Rules

| Risk | Mitigation |
| :--- | :--- |
| Stale Repository View | Run `rtk tnexus sync` before trusting architecture summaries after a large branch switch or codegen run. |
| No Direct Health Subcommand | The current CLI does not expose a first-class `health` command. Use `status`, `files`, `context`, and `cypher` to build an operational architecture view from the CLI. |
| Deep Structural Query | If a question goes beyond CLI summaries, query `.tnexus/tnexus.db` directly instead of dropping back to ad hoc filesystem scans. |
