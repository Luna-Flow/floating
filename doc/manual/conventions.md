# Repository conventions

These rules add to the Luna-Flow documentation standard for `floating`.
Documentation describes the **implementation on the current branch**. As of
`2026-09-06`, the release baseline is **`0.8.0`**.

## Chapters and guides

Each documented package has one page per chapter, named after its package path:

1. **API reference (`api/<package>.md`)** specifies public types, functions,
   methods, errors, and observable semantics.
2. **Tutorial (`tutorial/<package>.md`)** provides small executable workflows
   and usage guidance.
3. **Design (`design/<package>.md`)** explains representation, invariants,
   responsibility boundaries, and implementation tradeoffs.
4. **Conformance (`conformance/<package>.md`)** defines a pinned finite evidence
   claim and its exclusions for each numerical core: `bin_float`, `decimal`,
   `decimal_gda`, and `ball_float`.
5. **Performance (`performance/<package>.md`)** records reproducible
   measurements and target-specific dispatch evidence for the same cores
   without making API promises.

The manual also has cross-package guides: `getting_started.md` for package
selection, `numeric_semantics.md` for shared numerical vocabulary,
`architecture.md` for responsibility boundaries, `verification.md` for
conformance scope and reproducible commands, and `performance_audit.md` for the
optimization evidence of the historical performance baseline.

The repository `README.md` provides current-baseline positioning, package entry
points, and a reader path. `CHANGELOG.md` owns historical release notes and
migration history.

## Package pages

- Mirror every `moon.pkg` path: the package in `src/<path>/moon.pkg` is
  documented in `api/<path>.md`, `tutorial/<path>.md`, and `design/<path>.md`.
  File names do not create MoonBit modules; `moon.pkg` boundaries do.
- Give every package all three pages; packages without an application API must
  still publish their generated inventory, maintainer workflow, and stability
  boundary.
- Do not document planned APIs as existing. Generated `pkg.generated.mbti` files
  are the public-surface inventory; source and tests define behavior.
- Do not keep research notes as separate pages. Promote durable conclusions
  into design, conformance, or performance pages; move superseded history to
  `CHANGELOG.md`.
- Keep `README.md` focused on the current baseline. Move superseded release
  narratives to `CHANGELOG.md`.
- In translations, do not translate identifiers, package names, paths,
  commands, or version strings.

## Numeric documentation rules

- Use `precision`, `rounding`, `classify`, `sign`, `normalized`, `quantum`,
  `context`, and `flags` consistently.
- Separate stored representation, exact value, rounded result, status flags,
  checked errors, and interval enclosure semantics.
- State when parsing preserves quantum and when normalization changes a cohort
  without changing its mathematical value.
- Never imply total ordering for NaN-containing scalars or interval values.
- For `*_ctx` APIs, document both the returned value and accumulated flags.
- For `*_checked` APIs, document the domain-specific state transition: result
  error, IEEE flag accumulation, or GDA trap short-circuit and recovery.
- Document `decimal` and `decimal_gda` as separate contracts: IEEE operations
  return per-operation flags, while GDA operations thread sticky status and
  traps through `GdaOutcome`.
- Keep examples small and checkable. MoonBit import examples must use `@lf_alg`
  for `Luna-Flow/luna-generic` and `@lf_arith` for `Luna-Flow/arithmetic`.

## Review checklist

- Compare package docs with `pkg.generated.mbti` after `moon info`.
- Check that every `moon.pkg` path still has its `api/`, `tutorial/`, and
  `design/` pages, then run `lunadoc update` and `lunadoc check` to verify links
  and the translation catalogs.
- Run `moon fmt`, `moon check --target all`, relevant tests, and documentation
  examples or the repository `just pr` gate as appropriate.
- Update the baseline date/version and changelog during a release bump.
