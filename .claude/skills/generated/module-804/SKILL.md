---
name: module-804
description: "Skill for the Module_804 area of code-preview.nvim. 12 symbols."
---

# Module_804

> 12 symbols | 6 files | Cohesion: 100%

## When to Use

- Working with code in `tests/`
- Modifying module_804-related functionality
- Exploring or calling `nvim_exec` entry points

## Key Files

| File | Symbols |
|------|---------|
| `tests/backends/codex/test_install.sh` | test_install_idempotent, test_install_refuses_corrupted_hooks_json, test_uninstall_handles_corrupted_hooks_json, test_uninstall_preserves_user_hooks |
| `tests/helpers.sh` | nvim_exec, reset_test_state |
| `tests/backends/copilot/test_install.sh` | test_install_idempotent, test_uninstall_copilot_hooks |
| `tests/backends/claudecode/test_install.sh` | test_install_idempotent, test_uninstall_claude_hooks |
| `tests/backends/claudecode/test_edit.sh` | test_visible_only |
| `tests/backends/socket/test_terminal_only.sh` | test_terminal_only_rejects_headless_target |

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `nvim_exec` | function | `tests/helpers.sh` | 199 |
| `reset_test_state` | function | `tests/helpers.sh` | 59 |
| `test_install_idempotent` | function | `tests/backends/codex/test_install.sh` | 56 |
| `test_install_idempotent` | function | `tests/backends/copilot/test_install.sh` | 67 |
| `test_install_idempotent` | function | `tests/backends/claudecode/test_install.sh` | 60 |
| `test_install_refuses_corrupted_hooks_json` | function | `tests/backends/codex/test_install.sh` | 248 |
| `test_terminal_only_rejects_headless_target` | function | `tests/backends/socket/test_terminal_only.sh` | 6 |
| `test_uninstall_claude_hooks` | function | `tests/backends/claudecode/test_install.sh` | 39 |
| `test_uninstall_copilot_hooks` | function | `tests/backends/copilot/test_install.sh` | 54 |
| `test_uninstall_handles_corrupted_hooks_json` | function | `tests/backends/codex/test_install.sh` | 274 |
| `test_uninstall_preserves_user_hooks` | function | `tests/backends/codex/test_install.sh` | 111 |
| `test_visible_only` | function | `tests/backends/claudecode/test_edit.sh` | 343 |

## How to Explore

1. `tnexus_context({name: "nvim_exec"})` — see callers and callees
2. `tnexus_search({query: "module_804"})` — search related symbols in the graph
3. Read key files listed above for implementation details

