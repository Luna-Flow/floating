# consistency design

## Design goal

`floating` has four numeric cores with overlapping claims: a binary value
converted to a decimal and back must denote the same rational number; the
checked wrappers must give the same values as the cores; an interval must
enclose the exact result of the scalar operation; all cores must round
through the same `internal` rules. Each package's own tests cannot see the
others. `consistency` is the one place where these cross-package laws are
written down and executed.

## Mathematical background

Every finite value of every core denotes a rational number. Let
$\llbracket\cdot\rrbracket$ map a value to $\mathbb{Q}$ (implemented by
`semantic`, with `internal.ExactRat` as canonical form). The laws the suite
checks have three shapes:

- **Agreement:** for values $x$ of package $A$ and $y$ of package $B$ that
  represent the same input, $\llbracket f_A(x) \rrbracket =
  \llbracket f_B(y) \rrbracket$ when both operations are exact, and the
  results are the two packages' roundings of the same real otherwise.
- **Exact oracles:** a helper or operation equals a `BigInt` or rational
  computation, for example `round_positive_div` against
  $\lfloor n/d \rfloor$ plus the rounding table, or `digits10` against powers
  of ten.
- **Enclosure:** for an interval operation $F$ and a point operation $f$,
  $x \in X \Rightarrow f(x) \in F(X)$, and enclosure relations behave as
  partial orders rather than total orders.

Representation laws are checked as well: GDA results keep the right cohort,
signed zero and NaN payload; interchange encodings round-trip bit for bit.

## Design decisions

### White-box tests only

The package has no source files besides tests, and imports the cores only
`for "wbtest"`. It therefore never becomes part of a library build and has
no API to maintain, while still being able to use internal helpers.

### Fixed witnesses from official corpora

Many decimal tests use rows of the official decTest suite as named
witnesses. They pin the exact cases that once disagreed between packages,
in-process and without the corpus download.

### Oracles over expectations

Where possible a test computes the expected result independently (with
`BigInt`, `ExactRat` or `semantic`) instead of hard-coding output strings, so
a law stays meaningful when formatting changes.

## Correctness / invariants

- A passing run shows that each stated law holds on its witnesses; it is
  finite evidence, not a proof for all inputs.
- Tests are deterministic and target-independent, so the same run on native,
  Wasm and JavaScript checks the same claims.

## Alternatives rejected

- **Putting cross-package tests into each package.** It would create
  test-only dependency cycles between the cores.
- **Property-based random testing only.** Random inputs rarely hit cohort
  boundaries and ties; fixed witnesses do.

## Boundaries

- No public API and no runtime code.
- No external corpora (that is the role of the conformance frontends) and no
  performance measurements (the `bench` packages).
