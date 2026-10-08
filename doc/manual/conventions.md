# Repository conventions

These rules add to the Luna-Flow documentation standard for `floating`; they
never relax it. The manual describes the implementation on the current branch.
The current release is **`0.8.0`**, the version in `moon.mod`.

## Chapters and guides

Every package has one page per chapter, named after its package path:

1. **API reference (`api/<package>.md`)**, titled `# <package> API`, starts
   with `## Purpose` and `## Importing` (the `moon.pkg` import and the aliases
   the examples use), then lists every public item of `pkg.generated.mbti`
   under a heading that names it in code, grouped by purpose: the first
   sentence says what the item does, an `mbti` block gives the signature,
   and the text states its laws and edge behaviour (errors, flags, NaN,
   signed zero, overflow), with a small `test` example for the important
   items. Closely related items may share one heading.
2. **Tutorial (`tutorial/<package>.md`)**, titled `# <package> tutorial`,
   states its goal in the first paragraph, maps tasks to items in an
   `| I want to | Use |` table, and continues with `## Quick start`,
   `## Everyday tasks`, `## Going further`, `## Common pitfalls` and
   `## Next steps`. Its examples are complete and compile.
3. **Design (`design/<package>.md`)**, titled `# <package> design`, explains
   the goal, the representation, the mathematics with its derivations, the
   invariants and the decisions taken, lists the alternatives rejected, and
   ends with `## Boundaries`.

The four numerical cores, `bin_float`, `decimal`, `decimal_gda` and
`ball_float`, have two more chapters, as the standard allows:

4. **Conformance (`conformance/<package>.md`)** states a pinned, finite
   evidence claim and its exclusions.
5. **Performance (`performance/<package>.md`)** records reproducible
   measurements and target-specific dispatch evidence without making API
   promises.

The guides are fixed by `tools/doc_quality.py`: `index.md` (overview and
package map), `getting_started.md` (package choice and first steps),
`numeric_semantics.md` (shared numerical vocabulary), `architecture.md`
(layers and responsibilities), `verification.md` (gates and conformance
scope), `performance_audit.md` (audit of the historical performance baseline)
and this page. Do not add or rename guides without updating that list.

`README.md` positions the current release and points into the manual.
`CHANGELOG.md` owns release history and migration notes.

## Package pages

- Mirror every `moon.pkg`: the package in `src/<path>/moon.pkg` is documented
  in `api/<path>.md`, `tutorial/<path>.md` and `design/<path>.md`. Files do not
  create packages; `moon.pkg` boundaries do.
- Give every package all three pages. Packages without an application API
  (frontends, CLIs, `internal/*`, `bench/*`, `consistency`, `doc_examples`)
  still document their generated interface, maintainer workflow and stability
  boundary.
- Every package also keeps a `src/<path>/README.mbt.md`.
- `pkg.generated.mbti` is the public-surface inventory; source and tests
  define behaviour. A method is documented as callable with dot syntax only if
  the `.mbti` lists it as `pub fn Type::name`; trait-implementation methods are
  not promoted implicitly and must be declared with `pub extend`.
- Do not document planned APIs as existing, and do not keep research notes as
  separate pages. Promote durable conclusions into design, conformance or
  performance pages, and move superseded history to `CHANGELOG.md`.
- Pages name only the current release. A page may mention an older release
  only when it carries a `<!-- historical-performance-baseline: X.Y.Z -->`
  marker for that version; `tools/doc_quality.py` rejects any other historical
  version.

## API snapshots

Every API page ends with `## Complete public interface`, whose body is an exact
copy of the package's `pkg.generated.mbti` between the markers
`<!-- generated-api-start -->` and `<!-- generated-api-end -->`, fenced as
`mbti`. Individual signatures in the page body are `mbti` blocks too.
`tools/doc_quality.py` compares the snapshot with the generated file (it also
accepts the older `moonbit` fence), so regenerate it whenever `moon info`
changes the interface.

## Numeric documentation rules

- Use `precision`, `rounding`, `classify`, `sign`, `normalized`, `quantum`,
  `context` and `flags` as defined in
  [numeric semantics](./numeric_semantics.md).
- Separate the stored representation, the exact value, the rounded result,
  status flags, checked errors and interval enclosures.
- State when parsing preserves the quantum and when normalization changes the
  cohort without changing the value.
- Name the order an API uses. `compare`, `<` and sorting are a total preorder
  that puts every NaN above every number; the IEEE partial order (with
  *unordered*) and `totalOrder` are separate APIs. Never imply a scalar order
  for interval values.
- For `*_ctx` APIs, document both the returned value and the flags.
- For checked APIs and wrappers, document the domain-specific transition: a
  result error, IEEE flag accumulation, or a GDA trap short-circuit and its
  recovery.
- Document `decimal` and `decimal_gda` as separate contracts: IEEE operations
  return per-operation flags, while GDA operations thread sticky status and
  traps through `GdaOutcome`.
- Write mathematics in TeX (`$…$`, `$$…$$`) and cite the standard clause or
  classical result a derivation relies on.

## Examples

- Runnable examples are complete top-level items, normally a `test` block,
  fenced `moonbit`, and they show their output with `inspect`. They must
  compile and pass against the current branch.
- Partial snippets, signatures in prose, executable-package code and
  `internal/*` code that cannot be imported from outside the module, and
  `moon.pkg` snippets are fenced `moonbit nocheck`; shell commands are fenced
  `bash`. `tools/check_doc_examples.py`, run by `just docs`, compiles and runs
  every other `moonbit` block of the manual.
- Import aliases: `@lf_alg` for `Luna-Flow/luna-generic` and `@lf_arith` for
  `Luna-Flow/arithmetic`; floating packages use their default aliases
  (`@bin_float`, `@decimal`, …).
- Call only what the `.mbti` lists. For example, `BinFloat` has no
  `to_double` or `is_finite` method; use `to_shortest_string` and
  `@def.is_finite(x)`.

## Translations

English pages in `doc/manual` are the only source. Translations live in the
gettext catalogs `doc/locale/<locale>/LC_MESSAGES/manual.po` for the locales in
`doc/conf.json` and are never edited as page copies. Do not translate
identifiers, package names, paths, commands, version strings or mathematics.
Typst attachments live in `doc/attachments/` and are shared by all locales.

## Review checklist

1. Run `moon info` and compare each changed `pkg.generated.mbti` with its API
   page; refresh the `## Complete public interface` snapshot.
2. Check that every `moon.pkg` still has its `api/`, `tutorial/` and `design/`
   pages (and the evidence pages of the four cores).
3. Compile and run every changed example (`moonbit` blocks) against the
   current branch.
4. Run `just docs`: `tools/doc_quality.py`, the manual examples and the
   `src/doc_examples` tests.
5. Run `lunadoc update` to refresh `doc/locale/manual.pot` and merge the
   catalogs, translate new and fuzzy entries, then check `lunadoc status`
   (coverage per locale) and `lunadoc check --compile` (layout, catalogs,
   links and Typst attachments).
6. Run `moon fmt`, `moon check --target all --deny-warn`, the relevant tests,
   and `just pr` before submitting.
7. On a release bump, update `moon.mod`, the version in `README.md`, this page
   and `CHANGELOG.md` together.
