---
name: tnexus-impact-analysis
description: "Use when you want to know what will break if you modify a core struct/function, or perform safety analysis before refactoring a public API."
---

# CLI-First Blast Radius and Dependency Impact Analysis

## When to Use

- "Is it safe to change this function's return type?"
- "What modules depend on this struct?"
- "Are there any circular dependencies in this directory?"
- "Map the blast radius of modifying this configuration key."

## Workflow

```
1. rtk tnexus sync
2. rtk tnexus context "what breaks if I change X" --format markdown
3. rtk tnexus cypher "<query>" --json
4. Assess Risk: Wide dependency fan-out or repeated file hits → Consider a translation layer or deprecation period.
```

## Core Safety Moves

### 1. Blast Radius Map (Upstream Impact)
- **`rtk tnexus context "what breaks if I change X"`**: Start with a graph-backed impact summary in natural language.
- **`rtk tnexus query "X"`**: Narrow the symbol set before deeper graph inspection.
- **`rtk tnexus impact <node-id>`**: Use the dedicated impact subcommand once you have the stable node id.
- **`rtk tnexus callers <node-id>` / `rtk tnexus callees <node-id>`**: Expand nearby edges when the impact radius needs more directional detail.
- **Why this works**: For most impact checks, a good context prompt surfaces the dependent files and adjacent symbols faster than manual edge walking.

### 2. File-Level Circular Dependency Audits
- **`rtk tnexus cypher "<query>" --json`**: Use read-only graph queries to inspect suspicious dependency loops or tight file clusters.
- **Why this is critical**: Adding a reference that introduces a circular dependency (A $\to$ B $\to$ C $\to$ A) degrades modularity and makes refactors brittle. The CLI path for exact proof is currently `cypher`, not a dedicated `circular` subcommand.

### 3. fragile Dependency Chains
- **`rtk tnexus files --filter "<dir>"`**: Confirm the indexed directory scope being analyzed before deeper impact work.
- **`rtk tnexus context "identify fragile dependency chains in <dir>" --format markdown`**: Ask for a graph-backed summary of deep or sensitive areas.
- **`rtk tnexus cypher "<query>" --json`**: Use when you need exact edge-level evidence rather than a summary.
- `rtk rg` is a fallback for raw string search or file/path lookup, not the default entrypoint for symbol lookup.

## Risk Rules

| Impact Level | Indicators | Recommended Action |
| :--- | :--- | :--- |
| **LOW** | Context output points to one or two local files | Apply edits directly and verify with focused tests. |
| **MEDIUM** | Context repeatedly surfaces several modules or repeated file clusters | Create a multi-step edit plan, then compute impacted tests with `rtk tnexus affected`. |
| **HIGH** | Cypher or context shows broad fan-out across many directories | **Refactoring Alert!** Do not patch blindly. Consider deprecation, an adapter layer, or a staged migration. |
