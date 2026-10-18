---
name: module-747
description: "Skill for the Module_747 area of code-preview.nvim. 4 symbols."
---

# Module_747

> 4 symbols | 2 files | Cohesion: 100%

## When to Use

- Working with code in `lua/`
- Modifying module_747-related functionality
- Exploring or calling `clean` entry points

## Key Files

| File | Symbols |
|------|---------|
| `deps/plenary.nvim/lua/plenary/path.lua` | make_relative, normalize |
| `lua/code-preview/pre_tool/shell_detect.lua` | clean, shell_unescape |

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `clean` | function | `lua/code-preview/pre_tool/shell_detect.lua` | 82 |
| `shell_unescape` | function | `lua/code-preview/pre_tool/shell_detect.lua` | 61 |
| `make_relative` | method | `deps/plenary.nvim/lua/plenary/path.lua` | 341 |
| `normalize` | method | `deps/plenary.nvim/lua/plenary/path.lua` | 363 |

## How to Explore

1. `tnexus_context({name: "clean"})` — see callers and callees
2. `tnexus_search({query: "module_747"})` — search related symbols in the graph
3. Read key files listed above for implementation details

