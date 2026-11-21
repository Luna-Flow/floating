# frontend/testfloat_expr design

## Design goal

Berkeley TestFloat[^testfloat] generates test vectors for IEEE 754 binary
arithmetic from the SoftFloat reference implementation, for every format,
rounding direction and tininess mode. This package executes such vectors
against `binary` with bit-exact comparison of results and exception flags.
It is the evidence behind the IEEE 754 claims in
[binary conformance](../../conformance/binary.md). The package is pure;
vector generation and process orchestration live in `tools/`.

[^testfloat]: J. R. Hauser, *Berkeley TestFloat* and *Berkeley SoftFloat*,
    release 3e.

## Mathematical background

### Formats and encodings

A binary interchange format with width $k$, precision $p$ and maximum
exponent $e_{\max}$ (binary16: $(16, 11, 15)$, binary32: $(32, 24, 127)$,
binary64: $(64, 53, 1023)$, binary128: $(128, 113, 16383)$, with
$e_{\min} = 1 - e_{\max}$) represents $\pm 0$, subnormals, normals,
$\pm\infty$ and NaNs. Its encoding $\operatorname{enc} : \mathbb{F} \to
\{0,1\}^k$ is injective on non-NaN values and distinguishes $+0$ from $-0$.
TestFloat writes operands and results as $\operatorname{enc}$ in hexadecimal.

### Correctly rounded operations and flags

For an operation $\mathrm{op}$ and operands $x$, IEEE 754 requires the result
$r = \circ_\rho(\mathrm{op}(x))$, rounded once to the format in direction
$\rho$, and a set of exceptions[^ieee754]:

- *invalid* for operations with no meaningful result (for example
  $\infty \cdot 0$, $\sqrt{-1}$, a signaling NaN operand, an out-of-range
  integer conversion);
- *division by zero* for an exact infinite result from finite operands;
- *overflow* when the rounded result with unbounded exponent exceeds the
  largest finite number;
- *underflow* when the result is *tiny* and inexact, where tininess is
  detected either **before rounding** ($0 < |\mathrm{op}(x)| < 2^{e_{\min}}$)
  or **after rounding** ($0 < |\circ_\rho^{\,p,\infty}(\mathrm{op}(x))| <
  2^{e_{\min}}$, rounding to $p$ bits with unbounded exponent);
- *inexact* when $r \ne \mathrm{op}(x)$.

SoftFloat reports them as the mask
$\text{inexact} = 1$, $\text{underflow} = 2$, $\text{overflow} = 4$,
$\text{infinite} = 8$, $\text{invalid} = 16$, printed as two hexadecimal
digits. The front end builds the same mask from the five flag accessors of `BinaryFlags`.

[^ieee754]: IEEE 754-2019, clause 7 (exceptions), clause 7.5 (underflow and
    the two tininess rules), clause 3.4 (binary interchange encodings).

### The pass rule

Let $\hat r$ be the `binary` result computed in
`format.context(rounding~, tininess~)` (for a format conversion, the result of
`convert_format` into the destination format), $\hat F$ its flags, and $(e, M)$
the expected encoding and mask. For arithmetic operations the executor packs
$\hat r$ into the bit fields of the format, without rounding, obtaining
$\operatorname{pack}(\hat r)$, which is undefined when $\hat r$ is not a number of
the format. The vector passes when

$$
\Bigl( \bigl(e \text{ is a NaN} \wedge \hat r \text{ is a quiet NaN}\bigr)
\vee \operatorname{pack}(\hat r) = e \Bigr)
\;\wedge\;
\operatorname{mask}(\hat F) = M .
$$

For integer conversions the value check is replaced by: if $16 \in M$ the
conversion must report invalid, otherwise it must return the integer whose
bit pattern is $e$. For comparisons it is equality of booleans. The flag masks
must always be equal.

## Design decisions

### Bit-exact results, NaNs by class

Comparing encodings makes the sign of zero, the choice between subnormal and
zero, and the exact boundary of overflow part of every test. NaNs are the
exception: IEEE 754 leaves the payload and sign of a NaN produced by an
invalid operation to the implementation (SoftFloat's default NaN has its own
pattern), so an expected NaN only requires the actual result to be a quiet
NaN. A signaling NaN as a result would fail, which is the IEEE requirement.

### The operation is judged, not the operation followed by a rounding

An earlier version encoded the result with `BinaryInterchange::from_binary`,
which first rounds to the format and adds the flags of that rounding. Every
vector then tested "the operation, then a rounding": an operation that returned
a value with more bits than the format, or below its smallest subnormal, or that
dropped the inexact flag, passed whenever the rounding happened to repair it. The
executor now packs the sign, the coefficient and the exponent of the result into
the fields of the format with the layout of the format written out in the front
end (precision, width, bias), and fails the vector with "result not in the
format" when the value does not fit: more significant bits than the precision, a
bit below the last place of the smallest subnormal, a leading bit above the
largest exponent. The same holds for the format conversions, where the operation
under test is `convert_format` and nothing rounds behind it. No flag is added by
the harness.

What stays shared with the code under test: the decoding of the operands
(`BinaryInterchange::from_hex` and `to_binary`; a wrong decoding changes the
result and shows as a mismatch with the vector, it cannot be compensated by the
packing, which is independent) and `Binary::to_hex` in the failure message. The
expected column is compared as the text of the vector, not decoded. A NaN column
is compared as a quiet NaN result; the payload and the sign of a NaN are not
compared.

### Exact flag masks

The mask comparison is an equality, so a missing inexact or an extra
underflow fails the vector, and the flags compared are those of the operation
alone.

### Invalid conversions by flags only

On invalid integer conversions SoftFloat returns platform-specific sentinel
integers, while `binary` returns `None` to say there is no integer result.
The executor therefore requires `None` exactly when the expected mask has the
invalid bit, and ignores the sentinel. Every other conversion is compared as
an integer bit pattern.

### One specification per document

A TestFloat run produces vectors for one function, rounding mode, tininess
mode and exactness. Recording these once in `TestFloatSpec` keeps vector lines
in TestFloat's own format, so files from `testfloat_gen` are used unchanged.

### Sharding by vector index

Vector $k$ belongs to shard $k \bmod n$. As in the
[gda_expr design](gda_expr.md), the shards are disjoint,
cover the file, have sizes $\lceil (N-i)/n \rceil$, and each vector's result is
independent of the others, so merged shard counts equal the serial counts.

## Correctness and invariants

**Soundness of a pass.** If the expected vector is correct, a passing arithmetic vector shows that
`binary` returned the correctly rounded, correctly encoded result and
raised exactly the IEEE exceptions, except for the NaN payload; a result that
is not a number of the format fails.

**Counter identity.** Every selected vector is executed:
$\text{selected} = \text{passed} + \text{failed}$, and
$\text{total} = N$, the number of vectors in the document.

**Totality.** Parsing turns every line into a vector or a diagnostic; arity
is checked against the operation, so execution never meets a vector with the
wrong number of operands.

**Complexity.** One `binary` operation and one packing per vector, linear
in the number of vectors.

## Alternatives rejected

- **Comparing decoded values numerically.** It would accept $-0$ for $+0$ and
  hide encoding errors in subnormals.
- **Requiring SoftFloat's NaN pattern.** That would test SoftFloat's
  implementation choice, not IEEE 754.
- **Requiring SoftFloat's invalid-conversion sentinels.** They differ between
  platforms and have no meaning in an API that reports invalid results as
  `None`.

## Boundaries

- Only binary16/32/64/128 and the operations of `TestFloatOperation` (the
  eighteen arithmetic, integer and comparison operations and the conversions
  between the binary formats); no conversions to or from decimal strings or from
  integers.
- Only the five IEEE rounding directions; TestFloat's round-to-odd is
  rejected by `TestFloatSpec::parse`.
- NaN payloads and signs are not compared.
- File reading, vector generation and the declared matrix are handled by
  [`cli/testfloat_expr_cli`](../cli/testfloat_expr_cli.md) and
  `tools/run_binary_interpreter.py`.
