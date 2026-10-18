---
name: module-300
description: "Skill for the Module_300 area of code-preview.nvim. 5 symbols."
---

# Module_300

> 5 symbols | 1 files | Cohesion: 100%

## When to Use

- Working with code in `lua/`
- Modifying module_300-related functionality
- Exploring or calling `bin_dir` entry points

## Key Files

| File | Symbols |
|------|---------|
| `lua/code-preview/backends/copilot.lua` | bin_dir, install, plugin_root, ps_hook_script, sh_hook_script |

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `bin_dir` | function | `lua/code-preview/backends/copilot.lua` | 13 |
| `install` | function | `lua/code-preview/backends/copilot.lua` | 65 |
| `plugin_root` | function | `lua/code-preview/backends/copilot.lua` | 3 |
| `ps_hook_script` | function | `lua/code-preview/backends/copilot.lua` | 22 |
| `sh_hook_script` | function | `lua/code-preview/backends/copilot.lua` | 21 |

## How to Explore

1. `tnexus_context({name: "bin_dir"})` — see callers and callees
2. `tnexus_search({query: "module_300"})` — search related symbols in the graph
3. Read key files listed above for implementation details

