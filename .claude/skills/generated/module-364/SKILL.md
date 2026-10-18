---
name: module-364
description: "Skill for the Module_364 area of code-preview.nvim. 5 symbols."
---

# Module_364

> 5 symbols | 1 files | Cohesion: 100%

## When to Use

- Working with code in `lua/`
- Modifying module_364-related functionality
- Exploring or calling `codex_dir` entry points

## Key Files

| File | Symbols |
|------|---------|
| `lua/code-preview/backends/codex.lua` | codex_dir, config_path, global_codex_dir, hooks_path, install |

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `codex_dir` | function | `lua/code-preview/backends/codex.lua` | 24 |
| `config_path` | function | `lua/code-preview/backends/codex.lua` | 32 |
| `global_codex_dir` | function | `lua/code-preview/backends/codex.lua` | 16 |
| `hooks_path` | function | `lua/code-preview/backends/codex.lua` | 31 |
| `install` | function | `lua/code-preview/backends/codex.lua` | 172 |

## How to Explore

1. `tnexus_context({name: "codex_dir"})` — see callers and callees
2. `tnexus_search({query: "module_364"})` — search related symbols in the graph
3. Read key files listed above for implementation details

