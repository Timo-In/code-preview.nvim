---
name: module-708
description: "Skill for the Module_708 area of code-preview.nvim. 4 symbols."
---

# Module_708

> 4 symbols | 2 files | Cohesion: 100%

## When to Use

- Working with code in `deps/`
- Modifying module_708-related functionality
- Exploring or calling `test_directory` entry points

## Key Files

| File | Symbols |
|------|---------|
| `deps/plenary.nvim/lua/plenary/test_harness.lua` | test_directory, test_file, test_paths |
| `deps/plenary.nvim/lua/plenary/tbl.lua` | unpack |

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `test_directory` | function | `deps/plenary.nvim/lua/plenary/test_harness.lua` | 180 |
| `test_file` | function | `deps/plenary.nvim/lua/plenary/test_harness.lua` | 195 |
| `test_paths` | function | `deps/plenary.nvim/lua/plenary/test_harness.lua` | 42 |
| `unpack` | function | `deps/plenary.nvim/lua/plenary/tbl.lua` | 22 |

## How to Explore

1. `tnexus_context({name: "test_directory"})` — see callers and callees
2. `tnexus_search({query: "module_708"})` — search related symbols in the graph
3. Read key files listed above for implementation details

