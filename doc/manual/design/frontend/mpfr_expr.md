# frontend/mpfr_expr design

## Design goal

GNU MPFR computes correctly rounded results of elementary functions at any
precision and in every rounding direction.[^mpfr] This package turns MPFR
output into executable checks for `bin_float`: a passing row shows that
`bin_float` returns the correctly rounded result (and the right exception
flags) for that input, precision and rounding mode. It is a pure library; the
data files and their provenance live in `testdata/bin_float/` and the
generators in `tools/`.

[^mpfr]: L. Fousse, G. Hanrot, V. Lefèvre, P. Pélissier, P. Zimmermann,
    "MPFR: A multiple-precision binary floating-point library with correct
    rounding", *ACM TOMS* 33(2), 2007.

## Mathematical background

### Correct rounding

Let $\mathbb{F}_p$ be the binary numbers with a $p$-bit significand and an
unbounded exponent, and $\circ_{p,\rho}$ rounding to $\mathbb{F}_p$ in
direction $\rho$. For a real function $f$ and $x \in \mathbb{F}_q$, the
correctly rounded result is

$$
y = \circ_{p,\rho}\bigl(f(x)\bigr), \qquad
\text{inexact} \iff f(x) \notin \mathbb{F}_p .
$$

MPFR returns $y$ and a ternary value whose sign says whether $y$ is below,
equal to or above $f(x)$; the generators turn it into the inexact field. At
special points the IEEE 754 rules apply: an invalid operation (for example
$\sqrt{-1}$, $\ln(-1)$) returns NaN with the invalid flag, and an exact
infinite result from finite operands ($\ln 0 = -\infty$) raises division by
zero.[^ieee]

[^ieee]: IEEE 754-2019, clauses 7.2 (invalid operation) and 7.3 (division by
    zero), and clause 9.2 for the recommended elementary functions.

### What a row asserts

Each format fixes $f$, the input $x$, the target precision $p$ and direction
$\rho$, and records MPFR's $y$ (and flags). The executor evaluates the
corresponding `bin_float` method in `BinaryContext::unbounded(p, rounding=ρ)`
and checks:

| Format | Value check | Flag check |
| --- | --- | --- |
| square root | $\hat y = y$ as `BinFloat` values (`==`) | none |
| integer power $x^n$ | $\hat y = y$ (`==`) | inexact equal; no underflow, overflow, division by zero, invalid |
| elementary | $\hat y \simeq y$ (`compare == 0`) | inexact, invalid, division by zero equal; no underflow, overflow |

`==` on `BinFloat` compares the stored representation, which is canonical for
a given value and precision, so it distinguishes $+0$ from $-0$ and NaN
payloads. `compare == 0` is numeric equality extended so that every NaN
compares equal to every NaN and $+0 = -0$.

## Design decisions

### An unbounded exponent range

MPFR's default exponent range is far wider than any IEEE format, and the data
contains results such as $2^{-563}$ computed from subnormal-range binary64
inputs. Executing in an unbounded context tests rounding of the significand in
isolation: range effects (overflow, underflow, subnormals) are covered by the
TestFloat corpus through [`testfloat_expr`](testfloat_expr.md), where formats
have real limits. Consequently an underflow or overflow flag in an MPFR row is
a failure: it can only come from a defect.

### Inputs read at 512 bits

Inputs are written in hexadecimal and are exact binary numbers. Reading
elementary and power inputs at 512 bits keeps every input of up to 512
significant bits exact, so the check concerns $f$, not the parsing of $x$. The
square-root format carries its own input precision and is read at it.

### Numeric comparison for elementary rows

The elementary matrix is generated for 29 functions across binary32/64/128
precisions and all six rounding modes. Its expected NaNs carry no payload
information, and IEEE 754 leaves the payload of a generated NaN to the
implementation, so the comparison treats all NaNs as equal. The same numeric
comparison identifies $+0$ and $-0$; the sign of an exact zero result is
therefore not checked by these rows.

### Certification failures are failures

`bin_float` evaluates elementary functions with certified error bounds and a
bounded refinement loop; when it cannot certify the rounding it returns an
error instead of a possibly wrong value. The executor counts such an error as
a failed row with its own message, so a corpus run also proves that
certification succeeded on every row.

### Line numbers as ids

Rows have no names in these formats, so ids are `op:LINE` (or `sqrt:LINE`,
`pow:LINE`). They are stable as long as the pinned file is unchanged, which
the SHA-256 pins in `testdata/bin_float/corpora.json` guarantee.

## Correctness / invariants

**Soundness of a pass.** If MPFR's $y$ is the correctly rounded value of
$f(x)$ (which MPFR guarantees), a passing square-root or power row shows
$\hat y = \circ_{p,\rho}(f(x))$ exactly, and a passing elementary row shows the
same up to the sign of zero and the NaN payload, together with the stated
flags.

**Counter identity.** Every parsed row is executed, so
$\text{total} = \text{passed} + \text{failed}$ and the parsed row count equals
`total_cases`.

**Determinism.** Each row's result depends only on the row.

**Totality of parsing.** Every non-comment line becomes a row or a diagnostic,
and a document is returned only when there is no diagnostic.

**Known abort.** An elementary row for `pow`, `hypot` or `atan2` whose second
operand is `-` passes the parser and aborts at execution (the executor calls
`unwrap` on the missing operand).

## Alternatives rejected

- **Comparing decimal strings.** Decimal output would need its own correctly
  rounded conversion; hexadecimal significands compare exactly.
- **Running in IEEE formats.** That would mix range and rounding effects and
  make most high-precision rows (precision 113 and above) impossible.
- **Linking MPFR at test time.** The data is generated once by small C
  programs and pinned, so the MoonBit test run needs no C dependency and works
  on every target.

## Boundaries

- Square-root rows check values only, not flags.
- Elementary rows do not check the sign of a zero result or NaN payloads.
- No exponent range, subnormals or overflow handling are exercised.
- Only the three formats above are understood; there is no general MPFR test
  file reader.
- File reading, format detection and exit codes are in
  [`cli/mpfr_expr_cli`](../cli/mpfr_expr_cli.md).
