---
name: tnexus-cli
description: "Use when you need to run terminal commands to interact with Tnexus, sync the project graph, inspect branch status, or query the index from the CLI."
---

# Tnexus CLI Subcommand Guide

## When to Use

- When files have changed outside the AI session and you need to synchronize the graph database.
- When tracking a new Git branch to analyze its code graph separate from other branches.
- When verifying the project status, database integrity, or cleaning orphaned databases.

## Workflow

All terminal commands must be executed using the `rtk` sandbox executor wrapper (e.g., `rtk tnexus status`).

```
1. rtk tnexus status        → Verify the database is present and check current node/edge counts.
2. rtk tnexus sync          → Synchronize the local database with changed files on disk.
3. rtk tnexus branch list   → View all tracked Git branches and their individual index sizes.
```

## `tnexus files` Usage Boundary

- **`rtk tnexus files` lists indexed files**. It does not rescan the filesystem.
- **`--pattern` matches the full relative path with a glob**, not a fuzzy filename search.
- Treat **file/path lookup** and **symbol lookup** as different tasks:
  - File/path lookup: locating paths such as `dashboard.vue` or `src/views/...`
  - Symbol lookup: locating function/method/type/trait/interface names such as `handleLogin`, `GraphStats`, or `UserService::create`
- Prefer examples such as:
  - `rtk tnexus files --pattern '**/*.vue'`
  - `rtk tnexus files --pattern '**/dashboard.vue'`
  - `rtk tnexus files --filter 'admin_vue/src/'`
- Common mistake:
  - `rtk tnexus files --pattern 'dashboard.vue'` only matches a project-root path named `dashboard.vue`, so nested files usually do not appear.
- Good use cases:
  - Verify whether a file type or directory is indexed.
  - Narrow the directory or file-type scope before `context`, `query`, `cypher`, or `affected`.
  - Check index coverage after `sync`.
- Not a good fit:
  - Fuzzy filename search.
  - File-content search.
  - Regex or contains-style path matching.
- Routing rule:
  - If the goal is file/path lookup, prefer `rtk rg --files | rtk rg '...'`.
  - If the goal is symbol lookup or semantic analysis, prefer the direct analysis subcommands first (`query`, `context`, `callers`, `callees`, `impact`, `node`, `read`).
  - Use `rtk rg '...'` for raw file-content search, or only as a fallback when Tnexus cannot answer a symbol question.

## Key CLI Commands

### 1. Initialization and Rebuilding
- **`rtk tnexus init`**: Creates the `.tnexus/` folder, bootstraps the SQLite database, and automatically outputs these AI Skills to `.claude/skills/tnexus/`.
- **`rtk tnexus doctor`**: Performs an integrity check on the SQLite index and automatically rebuilds the graph if corruption or missing sentinels are detected.
- **`rtk tnexus sync --force`**: Forces a full rebuild when incremental sync is no longer trustworthy.

### 2. Multi-Branch Tracking
`Tnexus` allows you to track multiple Git branches in parallel. Each branch gets its own database sandbox. When you checkout a new branch in Git, the CLI automatically detects it:
- **`rtk tnexus branch add <name>`**: Tracks a new branch. It automatically bootstraps its database from its nearest common Git ancestor to save indexing time.
- **`rtk tnexus branch list`**: Shows all active branch indices and their DB disk footprints.

### 3. Graph Query Entrypoints
- **`rtk tnexus query "<term>" --limit 20`**: Search symbols by name.
- **`rtk tnexus context "<task>" --format markdown`**: Build a graph-backed context pack for a coding task.
- **`rtk tnexus callers <node-id>`**: Show caller edges for a specific node id.
- **`rtk tnexus callees <node-id>`**: Show callee edges for a specific node id.
- **`rtk tnexus impact <node-id>`**: Show the impact radius of a symbol by node id.
- **`rtk tnexus node <node-id>`**: Inspect a single graph node in detail.
- **`rtk tnexus read <file> --mode full|lines|map|signatures`**: Read source or graph-backed file structure through the same modes as `tnexus_read`.
- **`rtk tnexus files --pattern '**/*.rs'`**: List indexed files by path glob when you need to confirm indexed boundaries without scanning the filesystem again.
- **`rtk tnexus cypher "<query>" --json`**: Run read-only structural graph queries when a higher-level subcommand is not available.

## Risk Rules

| Rule | Details | Action |
| :--- | :--- | :--- |
| **Command Wrapper** | Never call commands bare. | Always prefix commands with `rtk` (e.g., `rtk tnexus sync`). |
| **Dirty Sentinel** | If sync crashes. | `Tnexus` automatically cleans stale dirty files on the next open/sync. |
