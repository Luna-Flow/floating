# Documentation Standard

This repository's documentation should describe the **current implementation on
the branch**. As of `2026-06-06`, the active documentation baseline is
**`0.2.0`**.

## Document Types and Organization

### Main Document Types

1. **API Reference Documentation (`api.md`)** - Public interface details for packages and types
2. **User Guide (`tutorial.md`)** - User-oriented examples and usage guidance
3. **Design Documentation (`design.md`)** - Representation, normalization, and algorithm notes for maintainers

### Documentation Organization Principles

- Organize docs by package and then by responsibility, for example:

  ```txt
  doc/
    |- en_US
    |- ja_JP
    |- zh_CN
        |- def
        |- bin_float
        |- decimal
        |- ball_float
  ```

- Keep documentation aligned with the code structure.
- Do not document APIs or behaviors that are not already present in the repository implementation.

## Shared Rules Across Numeric Packages

### API Alignment

- `bin_float`, `decimal`, and `ball_float` should expose aligned names whenever the semantics are intentionally shared.
- When package behavior differs, the docs must state the difference explicitly and describe the intended usage.
- Every new public API should be considered for cross-package naming alignment by default.

### Semantic Clarity

- Separate exact representation semantics from rounded conversion semantics.
- Document normalization rules, especially when constructors canonicalize internal state.
- When a package uses enclosure semantics, describe containment and overlap behavior instead of implying exact-real semantics.

### Documentation Requirements

- Use consistent terminology for `precision`, `rounding`, `classify`, `sign`, and `normalized`.
- Distinguish public contracts from implementation details.
- Keep numeric examples small, checkable, and consistent with the current code.
- Benchmark and performance-reporting docs are out of scope for this repository baseline.
