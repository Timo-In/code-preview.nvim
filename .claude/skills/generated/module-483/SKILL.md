---
name: module-483
description: "Skill for the Module_483 area of code-preview.nvim. 6 symbols."
---

# Module_483

> 6 symbols | 1 files | Cohesion: 100%

## When to Use

- Working with code in `deps/`
- Modifying module_483-related functionality
- Exploring or calling `CollectObjectReferenceInMemory` entry points

## Key Files

| File | Symbols |
|------|---------|
| `deps/plenary.nvim/lua/plenary/profile/memory_profiler.lua` | CollectObjectReferenceInMemory, CollectSingleObjectReferenceInMemory, CreateObjectReferenceInfoContainer, CreateObjectReferenceInfoContainerFromFile, DumpMemorySnapshot (+1) |

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `CollectObjectReferenceInMemory` | function | `deps/plenary.nvim/lua/plenary/profile/memory_profiler.lua` | 144 |
| `CollectSingleObjectReferenceInMemory` | function | `deps/plenary.nvim/lua/plenary/profile/memory_profiler.lua` | 381 |
| `CreateObjectReferenceInfoContainer` | function | `deps/plenary.nvim/lua/plenary/profile/memory_profiler.lua` | 49 |
| `CreateObjectReferenceInfoContainerFromFile` | function | `deps/plenary.nvim/lua/plenary/profile/memory_profiler.lua` | 75 |
| `DumpMemorySnapshot` | function | `deps/plenary.nvim/lua/plenary/profile/memory_profiler.lua` | 960 |
| `DumpMemorySnapshotComparedFile` | function | `deps/plenary.nvim/lua/plenary/profile/memory_profiler.lua` | 1006 |

## How to Explore

1. `tnexus_context({name: "CollectObjectReferenceInMemory"})` — see callers and callees
2. `tnexus_search({query: "module_483"})` — search related symbols in the graph
3. Read key files listed above for implementation details

