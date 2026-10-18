---
name: module-665
description: "Skill for the Module_665 area of code-preview.nvim. 6 symbols."
---

# Module_665

> 6 symbols | 3 files | Cohesion: 100%

## When to Use

- Working with code in `lua/`
- Modifying module_665-related functionality
- Exploring or calling `executable_name` entry points

## Key Files

| File | Symbols |
|------|---------|
| `lua/code-preview/binary.lua` | executable_name, install_path, resolve |
| `backends/opencode/index.ts` | readBinPath, resolveHookEntry |
| `tests/backends/opencode/harness.ts` | main |

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `executable_name` | function | `lua/code-preview/binary.lua` | 19 |
| `install_path` | function | `lua/code-preview/binary.lua` | 52 |
| `main` | function | `tests/backends/opencode/harness.ts` | 19 |
| `readBinPath` | function | `backends/opencode/index.ts` | 34 |
| `resolve` | function | `lua/code-preview/binary.lua` | 61 |
| `resolveHookEntry` | function | `backends/opencode/index.ts` | 26 |

## How to Explore

1. `tnexus_context({name: "executable_name"})` — see callers and callees
2. `tnexus_search({query: "module_665"})` — search related symbols in the graph
3. Read key files listed above for implementation details

