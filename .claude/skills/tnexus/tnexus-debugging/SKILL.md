---
name: tnexus-debugging
description: "Use when compiling fails, tests are broken, or you need a CLI-first way to narrow relevant symbols, impacted files, and affected tests before verification."
---

# CLI-First Debugging and Test Verification with Tnexus

## When to Use

- "Why is this compile error happening?"
- "Run tests affected by my recent changes."
- "Show me which tests cover this specific function."
- "What functions are missing unit tests?"

## Workflow

```
1. rtk tnexus sync                 → Refresh the graph before debugging.
2. rtk tnexus context "explain this compiler failure and its likely callers" --format markdown
3. rtk tnexus read src/path/to/file.rs --mode lines --lines 120-180
4. Fix the code...
5. rtk tnexus affected <changed-file> --json
```

## Key CLI Moves

### 1. Refresh Graph State Before Trusting Any Diagnosis
- **`rtk tnexus sync`**: Update the local graph after edits, rebases, generated files, or test additions.
- **Why this matters**: Debug output is only as good as the current index. If the graph is stale, every downstream query becomes less reliable.

### 2. Build Task Context Instead of Guessing from Raw Stderr
- **`rtk tnexus context "<task>" --format markdown`**: Summarize the most relevant symbols, files, and relationships for the failure you are investigating.
- **`rtk tnexus query "<symbol or error keyword>" --limit 20`**: Jump from an error message to likely symbol definitions without raw file scanning.
- **`rtk tnexus node <node-id>`**: Inspect the exact graph node once you know the stable id.
- **`rtk tnexus read <file> --mode lines --lines A-B`**: Pull only the relevant source span without a separate raw-file fallback.
- **Why this is powerful**: It keeps debugging grounded in indexed code relationships instead of line-by-line grep alone.

### 3. Check Indexed Test Boundaries Before Running the Suite
- **`rtk tnexus files --pattern '**/*test*'`**: Lists indexed test-like paths when you need to confirm the verification surface.
- **Why this is useful**: It tells you what test files are already present in the graph, not what exists anywhere on disk.
- If the goal is file/path lookup for test files, prefer `rtk rg --files | rtk rg 'test'`.
- For symbol lookup such as failing function/method/type names, stay on `rtk tnexus query` / `context`; `rtk rg` is only a raw-text fallback.

### 4. Calculate Affected Tests Before Running the Whole Suite
- **`rtk tnexus affected <changed-file>`**: Return test files affected by the changed source paths.
- **`rtk tnexus affected --stdin --json`**: Feed a list of changed files via stdin when several files are involved.
- **Why this is powerful**: You can derive a focused verification set first, then hand the resulting paths to your language-native test runner.

### 5. Use Cypher When You Need Structural Clues
- **`rtk tnexus cypher "<query>" --json`**: Use read-only graph queries to inspect dependency edges or file clusters when `query` and `context` are too coarse.
- **Why this is powerful**: It gives you a CLI route for graph-level debugging without switching back to MCP tool calls.

## Risk Rules

| Risk | Mitigation |
| :--- | :--- |
| Stale Graph | If you added code, generated files, or tests but did not run `rtk tnexus sync`, the affected-test set and context output can drift from reality. |
| Missing Direct CLI Equivalent | Some MCP-only helpers such as AST-mapped diagnostics or test-risk ranking still do not have a first-class CLI subcommand. Prefer direct CLI analysis commands first, then fall back to `rtk tnexus cypher` when no dedicated subcommand exists. |
| Test Timeout | `rtk tnexus affected` only computes the candidate test files. You still need to run the real test command with your normal timeout controls. |
