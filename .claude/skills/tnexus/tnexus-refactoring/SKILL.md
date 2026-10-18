---
name: tnexus-refactoring
description: "Use when you want to rename, extract, split, move, or restructure code safely. Establishes a CLI-first SOP for mapping symbols, dependencies, and verification scope before editing."
---

# Safe CLI-First Refactoring and Restructuring with Tnexus

## When to Use

- "Rename this struct or method safely."
- "Add a new field to this struct and update all initializations."
- "Extract this logic into a separate file/module."
- Any task that involves modifying existing symbol definitions and their call sites.

## Workflow

```
1. rtk tnexus sync
2. rtk tnexus query "S" --limit 20
3. rtk tnexus context "refactor S safely and list likely call sites and dependent files" --format markdown
4. rtk tnexus cypher "<query>" --json
5. Plan update order: interfaces → implementations → callers → tests.
```

## Checklists

### 1. Rename / Modify Struct Field
- [ ] **Refresh the Graph**: Run `rtk tnexus sync` before trusting any refactor plan.
- [ ] **Locate the Symbol**: Run `rtk tnexus query "MyStruct"` to find the canonical symbol and likely definition files.
- [ ] **Map the Refactor Surface**: Run `rtk tnexus context "rename or modify MyStruct::my_field safely" --format markdown`.
- [ ] **Inspect the Exact Node**: Run `rtk tnexus node <node-id>` once the canonical symbol is known.
- [ ] **Read the Exact Source Slice**: Run `rtk tnexus read <file> --mode lines --lines A-B` before editing a critical block.
- [ ] **Escalate to Exact Graph Query if Needed**: Use `rtk tnexus cypher "<query>" --json` when the summary is not precise enough.
- [ ] **Verify Scope**: Compute impacted tests with `rtk tnexus affected` and then run the real test command for those files.

### 2. Refactor Call / Method Signature
- [ ] **Find the Definition**: Use `rtk tnexus query "<function>"` to locate the primary symbol.
- [ ] **Collect Dependents**: Use `rtk tnexus context "change the signature of <function> safely" --format markdown`.
- [ ] **Prove Edge Cases**: Use `rtk tnexus cypher "<query>" --json` for exact dependency edges or file-level evidence.
- [ ] **Modify Definition First**: Apply the signature change to the definition file before patching call sites.
- [ ] **Verify in Layers**: Use `rtk tnexus affected` to narrow tests, then run the actual compiler and tests.

## Key CLI Moves

**`rtk tnexus query`** — Search for the symbol you plan to rename or reshape:
```bash
rtk tnexus query "GraphStats" --limit 20
```

**`rtk tnexus context`** — Build a graph-backed refactor brief before touching code:
```bash
rtk tnexus context "add a field to GraphStats and identify dependent files" --format markdown
```

**`rtk tnexus files --filter "src/"`** — Confirm the indexed module or directory boundary before a structural change:
```bash
rtk tnexus files --filter "src/"
```

**`rtk tnexus cypher`** — Use exact graph queries when the summary needs proof:
```bash
rtk tnexus cypher "MATCH (n)-[r]->(m) RETURN n, r, m LIMIT 20" --json
```

Use `rtk rg` for raw string search or file/path lookup, not as the default entrypoint for symbol lookup.

## Risk Rules

| Risk Factor | Mitigation |
| :--- | :--- |
| Stale Graph Data | If you modified files and dependencies have shifted, run `rtk tnexus sync` before trusting the refactor map. |
| No Direct CLI Edit Primitive | The CLI helps you discover the refactor surface, but source edits should still be done with precise local patching tools rather than broad rewrites. |
| Summary Not Precise Enough | When `query` or `context` is too coarse, move to `rtk tnexus cypher` or direct SQLite queries instead of guessing. |
