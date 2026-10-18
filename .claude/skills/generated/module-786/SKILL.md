---
name: module-786
description: "Skill for the Module_786 area of code-preview.nvim. 11 symbols."
---

# Module_786

> 11 symbols | 5 files | Cohesion: 100%

## When to Use

- Working with code in `tests/`
- Modifying module_786-related functionality
- Exploring or calling `assert_contains` entry points

## Key Files

| File | Symbols |
|------|---------|
| `tests/backends/opencode/test_apply_patch.sh` | test_patch_add_file, test_patch_add_file_no_hunk_marker, test_patch_multi_file, test_patch_multiple_hunks, test_patch_update_file |
| `tests/backends/claudecode/test_install.sh` | test_install_claude_hooks, test_install_preserves_existing |
| `tests/backends/codex/test_install.sh` | test_install_codex_hooks, test_install_preserves_user_hooks |
| `tests/helpers.sh` | assert_contains |
| `tests/backends/copilot/test_install.sh` | test_install_copilot_hooks |

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `assert_contains` | function | `tests/helpers.sh` | 224 |
| `test_install_claude_hooks` | function | `tests/backends/claudecode/test_install.sh` | 13 |
| `test_install_codex_hooks` | function | `tests/backends/codex/test_install.sh` | 27 |
| `test_install_copilot_hooks` | function | `tests/backends/copilot/test_install.sh` | 20 |
| `test_install_preserves_existing` | function | `tests/backends/claudecode/test_install.sh` | 77 |
| `test_install_preserves_user_hooks` | function | `tests/backends/codex/test_install.sh` | 73 |
| `test_patch_add_file` | function | `tests/backends/opencode/test_apply_patch.sh` | 83 |
| `test_patch_add_file_no_hunk_marker` | function | `tests/backends/opencode/test_apply_patch.sh` | 123 |
| `test_patch_multi_file` | function | `tests/backends/opencode/test_apply_patch.sh` | 186 |
| `test_patch_multiple_hunks` | function | `tests/backends/opencode/test_apply_patch.sh` | 233 |
| `test_patch_update_file` | function | `tests/backends/opencode/test_apply_patch.sh` | 32 |

## How to Explore

1. `tnexus_context({name: "assert_contains"})` — see callers and callees
2. `tnexus_search({query: "module_786"})` — search related symbols in the graph
3. Read key files listed above for implementation details

