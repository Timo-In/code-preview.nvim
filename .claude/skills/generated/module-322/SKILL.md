---
name: module-322
description: "Skill for the Module_322 area of code-preview.nvim. 37 symbols."
---

# Module_322

> 37 symbols | 13 files | Cohesion: 100%

## When to Use

- Working with code in `deps/`
- Modifying module_322-related functionality
- Exploring or calling `add` entry points

## Key Files

| File | Symbols |
|------|---------|
| `deps/plenary.nvim/lua/luassert/spy.lua` | called, called_at_least, called_at_most, called_less_than, called_more_than (+1) |
| `lua/code-preview/log.lua` | debug, error, info |
| `deps/plenary.nvim/lua/plenary/async/uv_async.lua` | add |
| `lua/code-preview/pre_tool/shell_detect.lua` | detect_rm_paths |
| `deps/plenary.nvim/lua/plenary/fun.lua` | arify |
| `deps/plenary.nvim/lua/luassert/util.lua` | extract_keys |
| `deps/plenary.nvim/lua/plenary/enum.lua` | make_enum |
| `deps/plenary.nvim/lua/plenary/async_lib/async.lua` | callback_or_next |
| `lua/code-preview/rpc.lua` | dispatch |
| `lua/code-preview/health.lua` | check |

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `add` | function | `deps/plenary.nvim/lua/plenary/async_lib/uv_async.lua` | 5 |
| `add` | function | `deps/plenary.nvim/lua/plenary/async/uv_async.lua` | 5 |
| `arify` | function | `deps/plenary.nvim/lua/plenary/fun.lua` | 4 |
| `callback_or_next` | function | `deps/plenary.nvim/lua/plenary/async_lib/async.lua` | 9 |
| `called` | function | `deps/plenary.nvim/lua/luassert/spy.lua` | 138 |
| `called_at_least` | function | `deps/plenary.nvim/lua/luassert/spy.lua` | 161 |
| `called_at_most` | function | `deps/plenary.nvim/lua/luassert/spy.lua` | 166 |
| `called_less_than` | function | `deps/plenary.nvim/lua/luassert/spy.lua` | 176 |
| `called_more_than` | function | `deps/plenary.nvim/lua/luassert/spy.lua` | 171 |
| `called_with` | function | `deps/plenary.nvim/lua/luassert/spy.lua` | 123 |
| `check` | function | `lua/code-preview/health.lua` | 2 |
| `check_keys` | function | `deps/plenary.nvim/tests/plenary/iterators_spec.lua` | 4 |
| `debug` | function | `lua/code-preview/log.lua` | 40 |
| `detect_rm_paths` | function | `lua/code-preview/pre_tool/shell_detect.lua` | 699 |
| `dispatch` | function | `lua/code-preview/rpc.lua` | 27 |
| `error` | function | `lua/code-preview/log.lua` | 48 |
| `extract_keys` | function | `deps/plenary.nvim/lua/luassert/util.lua` | 311 |
| `freeze` | function | `deps/plenary.nvim/lua/plenary/tbl.lua` | 30 |
| `info` | function | `lua/code-preview/log.lua` | 41 |
| `make_enum` | function | `deps/plenary.nvim/lua/plenary/enum.lua` | 49 |

## How to Explore

1. `tnexus_context({name: "add"})` — see callers and callees
2. `tnexus_search({query: "module_322"})` — search related symbols in the graph
3. Read key files listed above for implementation details

