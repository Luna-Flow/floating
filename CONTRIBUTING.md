# Contribution Guidelines

This guide tracks the current repository workflow and follows the current
documentation baseline: **`0.10.2`**.

## To Contributors

We welcome contributors interested in arbitrary-precision numerics, floating-point
semantics, ball arithmetic, and MoonBit library design. This repository is still
early-stage, so contributions that improve correctness, documentation clarity,
trait design, and test coverage are especially valuable.

## Table of Contents

1. [Code Style](#1-code-style)
2. [Naming Conventions](#2-naming-conventions)
3. [Comments](#3-comments)
4. [File Standards](#4-file-standards)
5. [Commit Guidelines](#5-commit-guidelines)
6. [Release Checklist](#6-release-checklist)
7. [Code Review](#7-code-review)

## 1. Code Style

- The project follows the formatting style enforced by the MoonBit toolchain:

  ```bash
  moon fmt
  ```

- Run `moon fmt` before committing to keep the repository consistent. It formats both
  modules of the workspace (see [Two modules](#two-modules)).
- The repository targets the MoonBit toolchain 0.10.20 or later (`moonc` ≥ 0.10.20)
  and builds with `--deny-warn`. Promote a trait-implementation method to
  dot syntax explicitly with `pub extend`; implicit promotion is deprecated.
- Prefer `using`-imported names over repeated fully-qualified package references when the imported names are used repeatedly in a file.
- Keep public APIs explicit about numeric semantics. If a function normalizes, rounds, or widens an enclosure, document that behavior.
- Prefer small helper functions for normalization and rounding logic over repeating low-level integer manipulation inline.

### Two modules

The repository is a `moon.work` workspace of two modules:

| Module | Directory | Contents | Dependencies |
| --- | --- | --- | --- |
| `Luna-Flow/floating` (published) | `.` (`moon.mod`, `src/`) | the numeric packages: `def`, `internal`, `bin_float`, `decimal`, `decimal_gda`, `ball_float`, the `*_checked` tiers, `semantic`, `consistency` | `Luna-Flow/arithmetic`, `Luna-Flow/luna-generic` only |
| `Luna-Flow/floating-tools` (not published) | `tooling/` (`tooling/moon.mod`, `tooling/src/`) | benchmarks (`bench`), command-line programs (`cli`), the differential harness (`differential`), frontends (`frontend`, `numeric_expr`), `internal/conformance`, `internal/runner_cli`, `doc_examples` | the library from this working tree, plus `mare_mark`, `async`, `x`, `type_theory` |

A library package must never import the tools module or one of the tooling
dependencies; `tools/check_imports.py` (stage "IMPORTS: package independence"
of `just pr`) enforces it. The tools module resolves the library as the
workspace member, never as a published version.

Every `moon` command run anywhere in the workspace acts on both modules and uses
one `_build` directory at the root: `moon check --target all --deny-warn`,
`moon fmt`, `moon info` and `moon test` cover the library and `tooling/`.
`cd` and `-C` do not narrow a command. To narrow it, name a package with
`-p` or a package path:

```bash
moon test -p Luna-Flow/floating/decimal_gda --target native   # one library package
moon test src/bin_float --target native                       # a package path works too
moon test -p Luna-Flow/floating-tools/frontend/gda_expr       # one tools package
moon check --target native --deny-warn tooling/src/bench      # one directory
```

`moon tree` and `moon package` act on one module: run them in the directory of
that module (the repository root for the library, `tooling/` for the tools). `tools/*.py` and `justfile`
use these forms wherever a stage means one package.

## 2. Naming Conventions

### 2.1 Bindings

- Use **lowercase letters with underscores** for bindings.
- Names should reflect the mathematical role of the value when possible, for example `coefficient`, `exponent10`, `rounding_mode`.

### 2.2 Functions

- Use **lowercase letters with underscores** for package-level helper functions.
- Keep public method names aligned across `bin_float`, `decimal`, and `ball_float` when the semantics are intended to match.

### 2.3 Structs and Traits

- Use **PascalCase** for structs and traits.
- Trait names should describe a stable capability boundary, not a specific implementation detail.

### 2.4 Files and Packages

- Use **lowercase letters with underscores** for file names and package names.
- Keep files grouped by clear responsibility:
  - trait and shared semantic definitions in `def`
  - shared implementation helpers in `internal`
  - concrete numeric representations in their own packages

## 3. Comments

- Keep comments concise, accurate, and current.
- Explain non-obvious numeric invariants, normalization rules, or enclosure behavior.
- Avoid redundant comments that restate obvious syntax.

## 4. File Standards

### 4.0 Documentation Matrix

- Every `src/<path>/moon.pkg` and `tooling/src/<path>/moon.pkg` package has matching `doc/manual/api/<path>.md`,
  `doc/manual/tutorial/<path>.md`, and `doc/manual/design/<path>.md` pages.
- English pages in `doc/manual` are the only source. Translations live in the
  gettext catalogs under `doc/locale`; run `lunadoc update` after editing
  English pages and `lunadoc check` before submitting.
- Numerical conformance and performance evidence stays separate from API
  promises. Promote durable research conclusions into synchronized pages and
  keep historical release material in `CHANGELOG.md`.
- Refresh `pkg.generated.mbti` with `moon info`, then run `just docs` before
  submitting documentation changes. It runs `tools/doc_quality.py` (page
  coverage, generated API snapshots, links and anchors, current-version and
  GDA claims, package `README.mbt.md` coverage, and a guard against the retired
  `doc/<locale>` trees), then `tools/check_doc_examples.py`, and then the
  `tooling/src/doc_examples` tests. Catalog
  freshness is checked separately by `lunadoc check` and the `Docs` workflow.
- API pages end with a `## Complete public interface` snapshot of
  `pkg.generated.mbti`, fenced as `mbti`. Runnable `moonbit` examples must
  compile against the current branch, which `tools/check_doc_examples.py`
  enforces: it generates one throwaway package per manual page under
  `_generated_doc_examples` (in `tooling/src`, or in `src` for pages that use only the library), re-fences the examples so `moon` compiles them,
  runs them and removes the tree. Mark an example that cannot run with
  `moonbit nocheck`, and if a page introduces a new package alias, add it to
  `alias_map()` in that tool. See
  [Repository conventions](./doc/manual/conventions.md) for the full review
  checklist.

### 4.1 Folder Naming

- Use **lowercase** folder names.
- Folder names should describe the package responsibility directly.

### 4.2 File Organization

- Each file should focus on a single coherent concern.
- Avoid vague file names such as `utils.mbt`; prefer names that reflect the domain behavior.
- Public APIs should remain easy to discover from the package layout.

## 5. Commit Guidelines

### 5.1 Commit Messages

- Run the local verification commands before committing:

  ```bash
  just fmt
  just pr
  ```

- Commit messages should be in **English**, concise, and use Conventional Commits prefixes such as `feat:`, `fix:`, `refactor:`, `docs:`, or `test:`.

### 5.2 Commit Scope

- Keep commits small and focused.
- Avoid combining unrelated documentation, trait, and numeric behavior changes in one commit unless they are tightly coupled.

### 5.3 Separators in gate output and documentation

- Do not use the middle dot (U+00B7) as a separator in gate output, tool output, documentation or pull request text. It stays only where it is required, for example inside a transliterated personal name or in text quoted verbatim from another source.
- Stage and suite names are written `CATEGORY: detail`, for example `TEST: native`, `SMOKE: IEEE 754`, `DECIMAL_GDA: official decTest`.
- Facts joined in one line use a comma, for example `25,385/25,385 passed, 12m 00s` or `scope=quick, workers=4`.
- A product in prose or code text is written `*` in code and `\cdot` or `\times` inside `$...$` formulas. The katakana middle dot (U+30FB) inside a katakana compound is normal Japanese orthography and is left alone.
- Anything that parses a label (tests, scripts, the CI workflow) is updated in the same change.

## 6. Release Checklist

- Before publishing to Mooncakes, make sure `moon.mod` has already been bumped to the intended release version.
- Update `README.md`, the `doc/manual` pages, and (with `lunadoc update`) the translation catalogs if the package overview or release notes no longer match the implementation.
- Move superseded release notes to `CHANGELOG.md`; keep README files focused on the current baseline.
- Run the quick `just pr` gate for ordinary changes and the complete `just ci`
  gate before publishing.
- The GitHub Actions publish workflow reads the release version directly from `moon.mod`.
- If Mooncakes reports a duplicate version, bump the version before retrying.

## 7. Code Review

- All code submissions should undergo review.
- Reviews should focus first on numeric correctness, semantic clarity, and missing tests, then on style and cleanup.
- Changes that alter rounding, normalization, conversion, or enclosure behavior should include or update tests in `src/consistency`.
