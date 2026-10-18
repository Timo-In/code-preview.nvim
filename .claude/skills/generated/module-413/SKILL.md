---
name: module-413
description: "Skill for the Module_413 area of code-preview.nvim. 9 symbols."
---

# Module_413

> 9 symbols | 2 files | Cohesion: 100%

## When to Use

- Working with code in `deps/`
- Modifying module_413-related functionality
- Exploring or calling `band` entry points

## Key Files

| File | Symbols |
|------|---------|
| `deps/plenary.nvim/lua/plenary/bit.lua` | band, bit_band, bit_bor, bor, bswap (+3) |
| `deps/plenary.nvim/lua/plenary/path.lua` | is_dir |

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `band` | function | `deps/plenary.nvim/lua/plenary/bit.lua` | 178 |
| `bit_band` | function | `deps/plenary.nvim/lua/plenary/bit.lua` | 292 |
| `bit_bor` | function | `deps/plenary.nvim/lua/plenary/bit.lua` | 281 |
| `bor` | function | `deps/plenary.nvim/lua/plenary/bit.lua` | 181 |
| `bswap` | function | `deps/plenary.nvim/lua/plenary/bit.lua` | 224 |
| `btest` | function | `deps/plenary.nvim/lua/plenary/bit.lua` | 256 |
| `replace` | function | `deps/plenary.nvim/lua/plenary/bit.lua` | 216 |
| `tohex` | function | `deps/plenary.nvim/lua/plenary/bit.lua` | 198 |
| `is_dir` | method | `deps/plenary.nvim/lua/plenary/path.lua` | 679 |

## How to Explore

1. `tnexus_context({name: "band"})` — see callers and callees
2. `tnexus_search({query: "module_413"})` — search related symbols in the graph
3. Read key files listed above for implementation details

