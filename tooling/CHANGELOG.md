# Changelog of `Luna-Flow/floating-tools`

The developer tools of [`Luna-Flow/floating`](../library/README.md): benchmarks,
command-line programs, the corpus frontends, the differential harness and the
documentation examples. The module has the version of the library and imports the
library of that version; the changelog of the library is
[`library/CHANGELOG.md`](../library/CHANGELOG.md). An entry that changes only this
module goes here (see `CONTRIBUTING.md`, "Release Checklist").

## Unreleased

### Changed

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
