---
name: tnexus-exploring
description: "Use when you want to explore an unfamiliar part of the codebase, trace how a function is called, or find implementations of an interface."
---

# CLI-First Codebase Exploration with Tnexus

## When to Use

- "How does the authentication flow work?"
- "What calls this trait method?"
- "Show me an overview of this large module."
- When tracing code paths and dependencies before starting edits.

## Workflow

```
1. rtk tnexus query "X" --limit 20
2. rtk tnexus context "trace how X works and what codepaths matter" --format markdown
3. rtk tnexus callers <node-id>
4. rtk tnexus read src/path/to/file.rs --mode signatures
```

## Key CLI Moves

### 1. Hybrid Search
Use `rtk tnexus query` and `rtk tnexus context` to find symbols by name or semantic concept.
- **Bare search**: `rtk tnexus query "Database" --limit 20` matches likely symbol names.
- **Concept search**: `rtk tnexus context "loading configuration" --format markdown` performs graph-backed retrieval for semantically-related symbols.

### 2. Trait and Method Implementations
When exploring polymorphic code or interfaces:
- **`rtk tnexus query "<TraitName>"`**: Find the trait, interface, or type symbol quickly.
- **`rtk tnexus context "who implements <TraitName> and where is it used" --format markdown`**: Ask the graph for an implementation-oriented summary.
- **`rtk tnexus cypher "<query>" --json`**: Drop to Cypher when you need exact `implements` or `contains` edge traversal from the CLI.

### 3. Smart Call Graph Traversal with Trait-Dispatch
- **`rtk tnexus callers <node-id>`**: Traverse inbound call edges for a symbol once you know the node id.
- **`rtk tnexus callees <node-id>`**: Traverse outbound call edges and include trait-dispatch expansion.
- **`rtk tnexus impact <node-id>`**: Estimate the direct and transitive blast radius before editing.
- **SOP for AI**: Prefer the direct CLI subcommand first. Only drop to `rtk tnexus cypher` when you need a custom graph slice not exposed by a dedicated command.

### 4. Indexed File Boundary Checks
- **`rtk tnexus files --filter "src/"`**: Lists indexed files under a directory so you can confirm the indexed boundary first.
- **`rtk tnexus files --pattern '**/*.rs'`**: Narrows the indexed candidate set by full-path glob.
- Entry routing:
  - For symbol lookup such as function/method/type/trait/interface names, start with `rtk tnexus query`.
  - For call paths, implementations, usage, or impact, prefer `rtk tnexus callers`, `callees`, `impact`, `node`, and `read` before falling back to `context` or `cypher`.
  - For file/path lookup, use `rtk tnexus files` only to confirm indexed coverage; if you just need fuzzy file/path lookup, prefer `rtk rg --files | rtk rg '...'`.

## Risk Rules

| Challenge | Mitigation |
| :--- | :--- |
| Dynamic/Reflective Calls | Graph cannot statically trace reflection. Supplement CLI results with targeted source search if dynamic calls are suspected. |
| Generic Overloads | `rtk tnexus query` may surface several matching symbols. Narrow by namespace keywords, file path, or a more specific task prompt in `rtk tnexus context`. |
| Missing Call-Graph Subcommand | If a direct subcommand still does not answer the exact graph shape you need, drop to `rtk tnexus cypher` for custom edge traversal. |
