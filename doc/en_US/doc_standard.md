# Documentation Standard

Repository documentation describes the **implementation on the current branch**.
As of `2026-07-16`, the release baseline is **`0.7.1`**.

## Document Types And Ownership

1. **API reference (`api.md`)** specifies public types, functions, methods,
   errors, and observable semantics.
2. **Tutorial (`tutorial.md`)** provides small executable workflows and usage
   guidance.
3. **Design (`design.md`)** explains representation, invariants, responsibility
   boundaries, and implementation tradeoffs.
4. **Conformance (`conformance.md`)** defines a pinned finite evidence claim and
   its exclusions for each numerical core.
5. **Performance (`performance.md`)** records reproducible measurements and
   target-specific dispatch evidence without making API promises.
6. **README** provides current-baseline positioning, package entry points, and a
   reader path.
7. **CHANGELOG** owns historical release notes and migration history.

The locale root also exposes four cross-package guides: `getting_started.md`
for package selection, `numeric_semantics.md` for shared numerical vocabulary,
`architecture.md` for responsibility boundaries, and `verification.md` for
conformance scope and reproducible commands.

## Structure And Localization

- Mirror every `moon.pkg` path under the documentation tree. File names do not
  create MoonBit modules; `moon.pkg` boundaries do.
- Keep the Markdown file set and top-level section responsibilities aligned
  across `en_US`, `zh_CN`, and `ja_JP`.
- Do not keep locale-only research pages. Promote durable conclusions into
  synchronized design, conformance, or performance documents; move superseded
  history to `CHANGELOG.md`.
- Treat English as the structural source, then localize naturally. Do not
  translate identifiers, package names, paths, commands, or version strings.
- Keep README files focused on the current baseline. Move superseded release
  narratives to `CHANGELOG.md`.
- Do not document planned APIs as existing. Generated `pkg.generated.mbti` files
  are the public-surface inventory; source and tests define behavior.
- Give every package `api.md`, `tutorial.md`, and `design.md`; packages without
  an application API must still publish their generated inventory, maintainer
  workflow, and stability boundary.

## Numeric Documentation Rules

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

## Review Checklist

- Compare package docs with `pkg.generated.mbti` after `moon info`.
- Verify links and cross-language file alignment.
- Run `moon fmt`, `moon check --target all`, relevant tests, and documentation
  examples or the repository `just pr` gate as appropriate.
- Update the baseline date/version and changelog during a release bump.
