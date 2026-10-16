# One real-buffer extmark renderer replaces selectable layouts

This decision supersedes the earlier version of ADR-0003 that retained the
side-by-side renderer. The plugin now has one preview [renderer](../../CONTEXT.md#renderer):
the real target file buffer with extmark highlights. Files already visible are
reused; unseen files open in their own tabs.

The selectable `tab`, `vsplit`, and `inline` layouts maintained separate buffer,
window, highlight, and cleanup lifecycles. Go daemon updates already used a
fourth real-buffer path, which meant save cleanup and multi-file tab behavior
depended on which path last rendered the preview. A single renderer makes those
behaviors deterministic for every agent and update source.

## Considered Options

- **Keep selectable layouts.** Rejected: it preserves the lifecycle divergence
  that caused daemon-rendered marks to survive saves and files to replace one
  another unexpectedly.
- **Map every old layout name to the real-buffer renderer.** Rejected: the
  configuration would imply choices that no longer exist.
- **Remove layout selection and keep one real-buffer renderer** *(chosen)*.

## Consequences

- `diff.layout`, `diff.layouts`, side-by-side scratch buffers, `:diffthis`, and
  the unified inline buffer are removed.
- Hook previews and Go daemon updates share extmark rendering and cleanup.
- A preview never replaces an unrelated visible buffer. Each unseen file opens
  in a dedicated tab; repeated updates reuse the file's existing window.
- Saving or editing a rendered buffer clears all preview extmarks, even after
  repeated daemon renders.
