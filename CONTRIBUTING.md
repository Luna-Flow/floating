# Contribution Guidelines

This guide tracks the current repository workflow and follows the current
documentation baseline: **`0.11.0`**.

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
- The repository follows the latest MoonBit toolchain without a pin (CI installs
  `latest` on every run; today `moon 0.1.20261119`, `moonc` 0.10.22) and builds with
  `--deny-warn`. The library module builds with `moonc` ≥ 0.10.20; the tools module
  needs `moonc` ≥ 0.10.22, because the `differential` executable uses `async fn main`
  without importing `moonbitlang/async` (older compilers reject that, newer ones
  report the import as unused). Promote a trait-implementation method to
  dot syntax explicitly with `pub extend`; implicit promotion is deprecated.
- Prefer `using`-imported names over repeated fully-qualified package references when the imported names are used repeatedly in a file.
- Keep public APIs explicit about numeric semantics. If a function normalizes, rounds, or widens an enclosure, document that behavior.
- Prefer small helper functions for normalization and rounding logic over repeating low-level integer manipulation inline.

### Two modules

The repository is a `moon.work` workspace of two modules, each in its own directory (the root has no module; `moon.work` lists `./library` and `./tooling`). A published package is exactly its directory: `library/` holds `moon.mod`, `src/`, `README.md`, `LICENSE` and `CHANGELOG.md`; the manual, the corpora, the scripts and the workflows stay at the root and are not packaged.

| Module | Directory | Contents | Dependencies |
| --- | --- | --- | --- |
| `Luna-Flow/floating` (published) | `library/` (`library/moon.mod`, `library/src/`) | the numeric packages: `def`, `internal`, `binary`, `decimal`, `decimal_gda`, `interval`, the `*_checked` tiers | `Luna-Flow/arithmetic`, `Luna-Flow/luna-generic` only |
| `Luna-Flow/floating-tools` (same version as the library) | `tooling/` (`tooling/moon.mod`, `tooling/src/`) | benchmarks (`bench`), command-line programs (`cli`), the differential harness (`differential`), frontends (`frontend`, `numeric_expr`), `internal/conformance`, `internal/runner_cli`, `consistency` (the cross-package tests), `semantic` (the exact projection used by them), `doc_examples` | the library from this working tree, plus `mare_mark`, `async`, `x`, `type_theory` |

A library package must never import the tools module or one of the tooling
dependencies; `tools/check_imports.py` (stage "IMPORTS: package independence"
of `just pr`) enforces it. The tools module resolves the library as the
workspace member, never as a published version.

Every `moon` command run anywhere in the workspace acts on both modules and uses
one `_build` directory at the root: `moon check --target all --deny-warn`,
`moon fmt`, `moon info` and `moon test` cover the library and `tooling/`.
`cd` and `-C` do not narrow a command (`moon tree` and `moon package` are the exceptions below). To narrow it, name a package with
`-p` or a package path:

```bash
moon test -p Luna-Flow/floating/decimal_gda --target native   # one library package
moon test library/src/binary --target native                       # a package path works too
moon test -p Luna-Flow/floating-tools/frontend/gda_expr       # one tools package
moon check --target native --deny-warn tooling/src/bench      # one directory
```

`moon tree` and `moon package` act on one module: run them in the directory of
that module (`library/` or `tooling/`; `moon -C library package --frozen` from the
root). `-C DIR` makes a relative `--target-dir` relative to `DIR`, so pass an
absolute `CODEX_MOON_TARGET_DIR` to `tools/run_moon_clean_exec.sh` when you use it
(the `just publish` recipe does) to keep the one `_build` of the workspace root.
`tools/*.py` and `justfile` use these forms wherever a stage means one package.

The three `LICENSE` files (root, `library/`, `tooling/`) are byte-identical, which
`tools/check_imports.py` checks. Links in `library/README.md` that point outside
`library/` are absolute URLs: the package page of the registry cannot follow
relative links out of the package.

## 2. Naming Conventions

### 2.1 Bindings

- Use **lowercase letters with underscores** for bindings.
- Names should reflect the mathematical role of the value when possible, for example `coefficient`, `exponent10`, `rounding_mode`.

### 2.2 Functions

- Use **lowercase letters with underscores** for package-level helper functions.
- Keep public method names aligned across `binary`, `decimal`, and `interval` when the semantics are intended to match.

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

### 3.1 Tests state their oracle

An oracle that is not independent of the code under test is a serious problem (issue 624: a copy of a
reader was tested against its original, both were wrong, the tests passed). Every `test "..."` block of
`library/src` and `tooling/src` therefore carries a declaration in the comment block directly above it, and
`tools/check_test_oracles.py` (stage `ORACLES: test declarations` of `just pr`) refuses a block without one.
The levels are those of `RULES.md`; the form is:

```moonbit
///|
// oracle: A
// source: what produces the expected value
// shares: the functions the oracle and the code under test both use, or "nothing"
test "..." {
```

- `A` external: values written out from a standard or arithmetic, a corpus or program of another implementation
  (MPFR, libmpdec, TestFloat, ITF1788, Python `decimal`, `math.isqrt`). Say which, and that this library did not
  produce them.
- `B` independent inside the repository: another algorithm that shares only primitives which themselves have a
  level A oracle on the inputs used. Name them in `// primitives:`.
- `E` equivalence with the previous implementation. It counts only where that implementation has an A or B oracle
  on the same input class: name it in `// underneath:` with its level.
- `S` self-consistency (round trips, identities, `is_ok`): allowed, counted, never the only check of a value
  that has a specified result.
- `C` (the oracle is the code under test, a sibling written from the same source, a copy of its logic, a helper the
  code under test also calls, or a wrapper compared with what it wraps) is refused. Repair the test.

Worked examples, from the repair of issue 624's audit (PR 642):

- Level A: `interval basics: sqrt endpoints are the directed square roots`
  (`library/src/interval/interval_basics_wbtest.mbt`). The old test compared `sqrt` with a copy that made the same
  call (level C, it could not fail). The new one writes the exact roots out and takes the directed bounds of the
  irrational roots from Python `math.isqrt`: `oracle: A`, `source:` says so, `shares: nothing`.
- Level B: `optimized decimal coefficient primitives match BigInt boundaries`
  (`library/src/internal/decimal_kernel/coeff_kernel_wbtest.mbt`): core `BigInt` arithmetic is the oracle, the
  conversion `dec_coeff_from_bigint_repr`/`to_bigint` is shared, so `oracle: B` with `primitives:` naming them.
- Level S next to A: `interval coefficient constructor keeps exact bounded interval`
  (`tooling/src/consistency/core_wbtest.mbt`) compares the bounds with the written value 12 (A) and checks
  `is_common_interval` (S): `oracle: A, S`.
- Level E: the `*_old_*` equivalence tests of `interval` (`interval_basics_wbtest.mbt`) compare a rewrite with the
  previous implementation. They may declare `oracle: E` only with `underneath:` saying which level A or B oracle
  the previous implementation has on that input class; until they do, they are in the debt list.

A block, or the first 60 lines of its file, that states its level in plain words (`Oracle (level A): ...`, `ORACLE level A`,
`Oracle, level A`) is accepted and counted as `prose` by the tool (the form several authors used before the key form
existed); a statement whose first level is C is refused. Convert such a block to the key form when you touch it.

A file made of generated tables takes one `// oracle-file:` block in its first 60 lines instead (`producer:` a
program that exists in `tools/`, `input:`, `library-ran: no`).

The blocks that existed when the rule started are in `tools/oracle_debt.txt` with the grade the audit of 2026-11-21
gave them. The list can only shrink: a block leaves it with a valid declaration (remove its line and lower
`DEBT_LIMIT` in `tools/check_test_oracles.py`), or when it is deleted (say in the PR body what replaces it). A new
block is not in the list and must declare. A renamed block is a new block and must declare. The tool checks the
form; the reviewer checks that the level is true, that the source is independent, and that `shares` is complete.

## 4. File Standards

### 4.0 Documentation Matrix

- Every `library/src/<path>/moon.pkg` and `tooling/src/<path>/moon.pkg` package has matching `doc/manual/api/<path>.md`,
  `doc/manual/tutorial/<path>.md`, and `doc/manual/design/<path>.md` pages.
- English pages in `doc/manual` are the only source. Translations live in the
  gettext catalogs under `doc/locale`; run `lunadoc update` after editing
  English pages and `lunadoc check` before submitting.
- Numerical conformance and performance evidence stays separate from API
  promises. Promote durable research conclusions into synchronized pages and
  keep historical release material in `library/CHANGELOG.md`.
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

- A version bump changes both manifests together: the `version` of `library/moon.mod`, the `version` of `tooling/moon.mod` and the library version in the tools imports (`"Luna-Flow/floating@<version>"` in `tooling/moon.mod`) are always equal. The workspace resolves the library member whatever the import line says, so `tools/check_imports.py` (stage "IMPORTS: package independence" of `just pr`, and the first step of the publish workflow) fails when any of the three differs. There is no bump script: edit the three places, the changelog headings and the manual (`lunadoc update`) in one commit.
- Changelogs: an entry that changes the library goes to `library/CHANGELOG.md` (its `## Unreleased` section); an entry that changes only the tools module (benchmarks, command-line programs, frontends, the differential harness, the documentation examples) goes to `tooling/CHANGELOG.md`. A change to both goes to both, each with its own wording.
- Publishing: the publish workflow (`publish.yml`, input `module`) publishes `library` from `library/` or `tools` from `tooling/`, each after its package-contents check and `moon publish --dry-run`. A package is exactly its directory, so no ignore file is needed. Publish the library first: the tools module imports the library of its own version and the dry run resolves it against the registry. Whether and when the tools module is published is decided at release time. `just publish [library|tools|all]` builds the zip and checks it; it never publishes.
- Update `library/README.md`, the root `README.md`, the `doc/manual` pages, and (with `lunadoc update`) the translation catalogs if the package overview or release notes no longer match the implementation.
- Move superseded release notes to `library/CHANGELOG.md`; keep README files focused on the current baseline.
- Run the quick `just pr` gate for ordinary changes and the complete `just ci`
  gate before publishing.
- The GitHub Actions publish workflow reads the release version directly from the manifest of the selected module.
- Tag and GitHub release: create them together with the publish of the library, in the same sitting, never later from memory (the release before this rule was published on 2026-11-12 without a GitHub release, which was added by hand on 2026-11-20). When the `library` publish workflow has succeeded, tag the merge commit of the version bump and create the release from it:

  ```bash
  gh release create vX.Y.Z --target <merge commit of the version bump> \
    --title vX.Y.Z --notes-file <release notes>
  ```

  The notes are the `## X.Y.Z` section of `library/CHANGELOG.md` (rename the `## Unreleased` heading to `## X.Y.Z - date` in the bump commit, in both changelogs).
- The tools module gets the same tag and the same GitHub release, with its own notes as a second section: a `### Tools module (Luna-Flow/floating-tools X.Y.Z)` section copied from the `## X.Y.Z` section of `tooling/CHANGELOG.md`; when the tools module is also published, say so in that section (`moon add Luna-Flow/floating-tools@X.Y.Z`). Why one tag and one release: both modules always have the same version, one version can have one tag, a reader looks for the release of a version in one place, and the tools publish is optional, so a second release would often be empty. If the tools module ever gets a different version scheme, it gets its own tag prefix (`tools-vX.Y.Z`) and its own release at that time.
- If Mooncakes reports a duplicate version, bump the version before retrying.

## 7. Code Review

- All code submissions should undergo review.
- Reviews should focus first on numeric correctness, semantic clarity, and missing tests, then on style and cleanup.
- Changes that alter rounding, normalization, conversion, or enclosure behavior should include or update tests in `tooling/src/consistency`.
