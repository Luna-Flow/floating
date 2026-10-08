# doc_examples design

## Design goal

Keep one small, always-compiled set of examples for the main workflows of the
library, so that an API change that breaks a documented workflow fails the
documentation gate (`just docs`) immediately.

## Mathematical background

None; the examples restate behaviour specified on the API and design pages of
the packages they use.

## Design decisions

- **A literate test package.** MoonBit compiles `moonbit check` blocks of a
  package's `README.mbt.md` as tests, so the examples are readable Markdown
  and real tests at once, without a separate test file.
- **Few examples, many packages.** Each block exercises one workflow end to
  end; exhaustive behaviour belongs in each package's tests and in
  `consistency`.
- **Warnings are errors.** The gate runs with `--deny-warn`, so examples never
  show deprecated APIs.

## Correctness / invariants

- Every block is a test with a unique name and passes on the native target.
- The package has no runtime code and no public items.

## Alternatives rejected

- **Examples only inside the manual pages.** A package inside the module keeps
  a minimal set compiling with the ordinary test command, independent of any
  documentation tooling.

## Boundaries

- Not an API; nothing may import it.
- No performance or conformance evidence.
