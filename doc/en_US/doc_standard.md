# Documentation Standard

Repository documentation describes the **implementation on the current branch**.
As of `2026-07-11`, the active baseline is **`0.4.0`**.

## Document Types And Ownership

1. **API reference (`api.md`)** specifies public types, functions, methods,
   errors, and observable semantics.
2. **Tutorial (`tutorial.md`)** provides small executable workflows and usage
   guidance.
3. **Design (`design.md`)** explains representation, invariants, responsibility
   boundaries, and implementation tradeoffs.
4. **README** provides current-baseline positioning, package entry points, and a
   reader path.
5. **CHANGELOG** owns historical release notes and migration history.

## Structure And Localization

- Organize prose by MoonBit package. File names do not create MoonBit modules;
  `moon.pkg` boundaries do.
- Keep the Markdown file set and top-level section responsibilities aligned
  across `en_US`, `zh_CN`, and `ja_JP`.
- Treat English as the structural source, then localize naturally. Do not
  translate identifiers, package names, paths, commands, or version strings.
- Keep README files focused on the current baseline. Move superseded release
  narratives to `CHANGELOG.md`.
- Do not document planned APIs as existing. Generated `pkg.generated.mbti` files
  are the public-surface inventory; source and tests define behavior.
- Mark `internal`, CLI, test, and conformance infrastructure boundaries clearly.

## Numeric Documentation Rules

- Use `precision`, `rounding`, `classify`, `sign`, `normalized`, `quantum`,
  `context`, and `flags` consistently.
- Separate stored representation, exact value, rounded result, status flags,
  checked errors, and interval enclosure semantics.
- State when parsing preserves quantum and when normalization changes a cohort
  without changing its mathematical value.
- Never imply total ordering for NaN-containing scalars or interval values.
- For `*_ctx` APIs, document both the returned value and accumulated flags.
- For `*_result` APIs, document short-circuiting and the distinction between
  value-transforming composition and observer results.
- Keep examples small and checkable. MoonBit import examples must use `@lf_alg`
  for `Luna-Flow/luna-generic` and `@lf_arith` for `Luna-Flow/arithmetic`.

## Review Checklist

- Compare package docs with `pkg.generated.mbti` after `moon info`.
- Verify links and cross-language file alignment.
- Run `moon fmt`, `moon check --target all`, relevant tests, and documentation
  examples or the repository `just pr` gate as appropriate.
- Update the baseline date/version and changelog during a release bump.
