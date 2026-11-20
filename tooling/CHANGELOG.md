# Changelog of `Luna-Flow/floating-tools`

The developer tools of [`Luna-Flow/floating`](../library/README.md): benchmarks,
command-line programs, the corpus frontends, the differential harness and the
documentation examples. The module has the version of the library and imports the
library of that version; the changelog of the library is
[`library/CHANGELOG.md`](../library/CHANGELOG.md). An entry that changes only this
module goes here (see `CONTRIBUTING.md`, "Release Checklist").

## Unreleased

### Fixed

- The MoonBit toolchain of 2026-11-19 (`moon 0.1.20261119`, `moonc` 0.10.22) reports the import of `moonbitlang/async` in `tooling/src/differential/moon.pkg` as an unused package (error 0029 under `--deny-warn`), which turned CI red for `main` and every pull request from 2026-11-20 06:12 UTC ([#459](https://github.com/Luna-Flow/floating/issues/459)). `async fn main` needs no import any more; the import is removed. The module needs `moonc` ≥ 0.10.22. `supported_targets` (no wasm-gc) stays: the executable compiles for wasm-gc but the module fails to instantiate (`moon run --target wasm-gc`), and the `warnings = "-unused_package"` of the `bench/*` packages is still needed (removing it gives 14 errors on wasm-gc).

### Added

- The binary TestFloat gate (`tools/run_binfloat_interpreter.py`) and the `testfloat_expr` frontend run the format conversions `f16`, `f32`, `f64` and `f128` to every other format (`to_f16`, `to_f32`, `to_f64`, `to_f128`): the operand is read in the format of the function name and the result in the destination format; the narrowing pairs run all five rounding modes and both tininess rules, the widening pairs (exact) one task each. 66 more tasks and 52,632 more level-1 vectors (468 to 534 tasks); four smoke files of twelve rows ([#222](https://github.com/Luna-Flow/floating/issues/222)).

- `tooling/README.md` (the `readme` field of `tooling/moon.mod`) to the standard of the library's README: what the module is, how it is built, a quick start, the package table, the documentation and the contribution rules ([#22](https://github.com/Luna-Flow/floating/issues/22)).
- The manual pages of every package of this module follow the library's standard, and `tools/doc_quality.py` now checks it: the API page has Purpose, Importing, a heading for every public item and the complete interface; the tutorial has the `I want to` table, Quick start, Everyday tasks, Going further, Common pitfalls, Next steps and, for a package with public items, an example that compiles; the design page has the goal, the mathematical background, the decisions, the invariants, the rejected alternatives and the boundaries. Gaps found by the audit are filled: the tutorials of `cli/dispatch` and `differential/harness`, a Going further section for `bench/external`, headings for `MpfrRandomDocument` and `MpfrDecimalRandomDocument`, and compiled examples for the four `cli/*_expr_cli` runners, `internal/conformance` and `internal/runner_cli`.

### Changed

- The `testfloat_expr` front end builds the TestFloat flag mask from the five accessors of `BinaryFlags`, because `BinaryFlags::to_testfloat_bits` left the library ([#22](https://github.com/Luna-Flow/floating/issues/22)). The mask and every result are unchanged.
- The `testfloat_expr` front end, the `mpfr_expr` front end and the manual pages of the frontends call the renamed `bin_float` methods (`pown_ctx`, `compare_quiet_equal`, `compare_signaling_less` and the other five comparison predicates, [#22](https://github.com/Luna-Flow/floating/issues/22)). Every result is unchanged.
- The tutorials of the packages of this module no longer tell the reader to `moon add Luna-Flow/floating@0.10.2`, which does not contain them: they say that the packages belong to this module (a package of the workspace, or `moon add Luna-Flow/floating-tools@0.11.0` once it is published). The package map of the manual says which module each package belongs to and lists `cli/dispatch` and `differential/harness`.

- The module is versioned with the library: `version` is `0.11.0`, the version of
  `library/moon.mod`, and the manifest imports `Luna-Flow/floating@0.11.0`
  ([#22](https://github.com/Luna-Flow/floating/issues/22)). `tools/check_imports.py`
  fails when the two versions and the imported library version differ. The
  description no longer says that the module is not published.
- The module moved out of the library module ([#22](https://github.com/Luna-Flow/floating/issues/22)):
  `bench`, `cli`, `differential`, `frontend/*`, `numeric_expr`, `doc_examples`,
  `internal/conformance` and `internal/runner_cli` are packages of
  `Luna-Flow/floating-tools` and no longer of `Luna-Flow/floating`; their import
  paths are `Luna-Flow/floating-tools/<package>`. `cli` and `differential` are
  entry points only; their behaviour is in the new packages `cli/dispatch` and
  `differential/harness`. The history of these changes before this module had a
  changelog is in the changelog of the library.
