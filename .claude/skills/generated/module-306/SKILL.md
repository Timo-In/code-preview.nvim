---
name: module-306
description: "Skill for the Module_306 area of code-preview.nvim. 29 symbols."
---

# Module_306

> 29 symbols | 6 files | Cohesion: 100%

## When to Use

- Working with code in `tests/`
- Modifying module_306-related functionality
- Exploring or calling `nvim_eval` entry points

## Key Files

| File | Symbols |
|------|---------|
| `tests/backends/codex/test_edit.sh` | test_codex_bash_atomic_replace, test_codex_bash_html_comment_false_positive, test_codex_bash_rm, test_codex_bash_shell_write_created, test_codex_bash_shell_write_modified (+2) |
| `tests/backends/copilot/test_edit.sh` | test_copilot_bash_rm, test_copilot_create, test_copilot_edit, test_copilot_relative_path, test_copilot_str_replace_alias |
| `tests/backends/codex/test_apply_patch.sh` | test_codex_apply_patch_add, test_codex_apply_patch_mixed, test_codex_apply_patch_update |
| `tests/backends/copilot/test_apply_patch.sh` | test_copilot_apply_patch_add, test_copilot_apply_patch_mixed, test_copilot_apply_patch_update |
| `tests/helpers.sh` | nvim_eval |
| `tests/backends/claudecode/test_edit.sh` | test_bash_rm_detection |

## Key Symbols

| Symbol | Type | File | Line |
|--------|------|------|------|
| `nvim_eval` | function | `tests/helpers.sh` | 174 |
| `test_bash_rm_detection` | function | `tests/backends/claudecode/test_edit.sh` | 161 |
| `test_codex_apply_patch_add` | function | `tests/backends/codex/test_apply_patch.sh` | 81 |
| `test_codex_apply_patch_mixed` | function | `tests/backends/codex/test_apply_patch.sh` | 113 |
| `test_codex_apply_patch_update` | function | `tests/backends/codex/test_apply_patch.sh` | 46 |
| `test_codex_bash_atomic_replace` | function | `tests/backends/codex/test_edit.sh` | 173 |
| `test_codex_bash_html_comment_false_positive` | function | `tests/backends/codex/test_edit.sh` | 240 |
| `test_codex_bash_rm` | function | `tests/backends/codex/test_edit.sh` | 118 |
| `test_codex_bash_shell_write_created` | function | `tests/backends/codex/test_edit.sh` | 198 |
| `test_codex_bash_shell_write_modified` | function | `tests/backends/codex/test_edit.sh` | 145 |
| `test_codex_edit_passthrough` | function | `tests/backends/codex/test_edit.sh` | 61 |
| `test_codex_write_passthrough` | function | `tests/backends/codex/test_edit.sh` | 90 |
| `test_copilot_apply_patch_add` | function | `tests/backends/copilot/test_apply_patch.sh` | 93 |
| `test_copilot_apply_patch_mixed` | function | `tests/backends/copilot/test_apply_patch.sh` | 129 |
| `test_copilot_apply_patch_update` | function | `tests/backends/copilot/test_apply_patch.sh` | 54 |
| `test_copilot_bash_rm` | function | `tests/backends/copilot/test_edit.sh` | 158 |
| `test_copilot_create` | function | `tests/backends/copilot/test_edit.sh` | 122 |
| `test_copilot_edit` | function | `tests/backends/copilot/test_edit.sh` | 53 |
| `test_copilot_relative_path` | function | `tests/backends/copilot/test_edit.sh` | 186 |
| `test_copilot_str_replace_alias` | function | `tests/backends/copilot/test_edit.sh` | 89 |

## How to Explore

1. `tnexus_context({name: "nvim_eval"})` — see callers and callees
2. `tnexus_search({query: "module_306"})` — search related symbols in the graph
3. Read key files listed above for implementation details

