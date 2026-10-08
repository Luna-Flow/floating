# frontend/gda_expr design

## Design goal

The General Decimal Arithmetic specification[^gda] comes with a large corpus of
`.decTest` files: every row gives an operation, its operands, the context, the
exact expected result and the exact set of conditions it must raise. This
package turns that corpus into an executable, finite claim about
`decimal_gda`: a row *passes* only when `decimal_gda` produces the same
representation and the same conditions. The package is pure (text in,
summary out) so that it can be tested in-process, sharded, and driven by a thin
CLI.

[^gda]: M. F. Cowlishaw, *General Decimal Arithmetic Specification*, version
    1.70, and the accompanying decTest suite. IEEE 754-2019 adopted the same
    arithmetic for its decimal formats.

## Mathematical background

### Decimal data and contexts

A finite GDA number is a triple $(s, c, q)$ with sign $s \in \{0, 1\}$,
integer coefficient $c \ge 0$ and exponent $q$, and value
$(-1)^s \cdot c \cdot 10^{q}$. Different triples may have the same value: the
set of representations of one value is its *cohort*, for example
$(0, 20, -1)$ and $(0, 200, -2)$ for $2.0$ and $2.00$. The specification fixes
which member of the cohort each operation returns (the ideal exponent), so a
test row's expected result is a representation, not only a value. Special
values are $\pm\infty$ and quiet or signaling NaNs with an integer payload and
a sign.

A context $\kappa = (p, \rho, E_{\min}, E_{\max}, \mathit{clamp},
\mathit{extended})$ gives the precision, the rounding mode and the exponent
range. An operation $f$ computes the exact result, rounds it under $\kappa$ and
raises a subset of thirteen *conditions*: `Inexact`, `Rounded`,
`Lost_digits`, `Invalid_operation`, `Division_by_zero`, `Overflow`,
`Underflow`, `Subnormal`, `Clamped`, `Conversion_syntax`,
`Division_impossible`, `Division_undefined` and `Invalid_context`.

### Rows as operations

A row

```text
id  op  a1 … an  ->  x  c1 … cm
```

under the directive context $\kappa$ is lowered to the expression
$\mathsf{op}(a_1, \dots, a_n)$ of [`numeric_expr`](../numeric_expr.md) and
evaluated with two callbacks. The literal callback decodes each $a_j$ to a
`@decimal_gda.Decimal`:

- `#` followed by hexadecimal digits: an IEEE 754 interchange encoding,
  decoded in the format whose $(p, E_{\min}, E_{\max})$ equals the context
  ($(7, -95, 96)$, $(16, -383, 384)$ or $(34, -6143, 6144)$); in any other
  context the operand is invalid;
- `32#…`, `64#…`, `128#…`: decimal text rounded into that interchange format;
- otherwise decimal text (a leading `+` is dropped), parsed with precision
  $\max(64, p)$, which keeps every operand of up to that many significant
  digits exact. A longer operand is rounded half-even on input, so the
  operation then rounds a second time. Double rounding differs from one
  rounding exactly when the first rounding moves the exact value onto, or
  across, a rounding boundary of precision $p$: at $p = 9$ the operand
  $1000000014\,\underbrace{9\cdots9}_{56}\,5$ (67 digits) becomes
  $1000000015 \cdot 10^{57}$ at 64 digits, a tie at 9 digits, and
  `half_even` then gives $100000002 \cdot 10^{58}$ instead of the correct
  $100000001 \cdot 10^{58}$.

The operation callback maps the normalized name to one `decimal_gda`
function (for example `add` to `@decimal_gda.add`, `squareroot` to
`@decimal_gda.sqrt`, `comparetotal` to `@decimal_gda.compare_total`) and calls
it with a `@decimal_gda.GdaContext` built from $\kappa$ *with every trap
disabled*. The result is a value of one of four kinds (decimal, integer,
boolean, text) together with the set $F$ of raised conditions. Conversions
`tosci` and `toeng` read the raw operand text, because the conversion from
text is itself under test. Interchange-only operations (`canonical`, and
`apply`, `copy*` on `#` operands with a `#` result) work on the encoding and
return text.

### The pass rule

Let $v$ be the actual result, $F$ the actual condition set and $C$ the set of
listed conditions. Define $\widehat{C}$ by adding `Invalid_operation`
whenever $C$ contains `Division_impossible` or `Division_undefined` (both are
reported through the invalid-operation signal). The row passes if and only if

$$
\operatorname{match}(v, x) \;\wedge\; F = \widehat{C},
$$

where equality of flag sets is checked in both directions: a missing or an
extra condition fails the row. $\operatorname{match}$ depends on the expected
token $x$ and the kind of $v$:

| expected $x$ | actual $v$ | $\operatorname{match}(v, x)$ |
| --- | --- | --- |
| `?` | any | true (only the conditions are checked) |
| `#hex` | decimal | the interchange encoding of $v$ in the context's format equals $x$, ignoring letter case |
| `32#…`, `64#…`, `128#…` | decimal | $v$ equals the value of $x$ in that format numerically (`compare == 0`); the conditions raised by encoding $v$ in that format are added to $F$ |
| other text | decimal | $v$ prints exactly as $x$, or $\operatorname{compareTotal}(v, \operatorname{dec}(x)) = 0$ |
| other text | integer | the decimal text of $v$ equals $x$ |
| other text | boolean | $x$ is `true`/`1` for true or `false`/`0` for false, ignoring case |
| text | text | equal strings (ignoring case for `#hex`) |

The decimal case is exact on representations. IEEE 754 `totalOrder`[^total]
compares signs first, then classes, then numeric values, then exponents, and
orders NaNs by signaling bit and payload. Hence

$$
\operatorname{compareTotal}(a, b) = 0 \iff
\begin{cases}
(s_a, c_a, q_a) = (s_b, c_b, q_b) & \text{finite,} \\
s_a = s_b & \pm\infty, \\
s_a = s_b,\ \text{same signaling bit and payload} & \text{NaN,}
\end{cases}
$$

so `2.0` does not match `2.00`, `-0` does not match `0`, and `NaN12` does not
match `NaN`.

[^total]: IEEE 754-2019, clause 5.10, `totalOrder`. `Decimal::compare_total`
    implements it for `decimal_gda`.

## Design decisions

### Dispositions instead of failures for rows that are not tests

**Problem.** The official corpus contains rows that do not describe a scalar
computation: `#` placeholders for invalid or non-scalar encodings, `?`
operands from older versions, operations the library does not provide, and
rounding modes it does not know. Counting them as failures hides real
failures; dropping them silently overstates coverage.

**Choice.** Every selected row gets a disposition. `Diagnostic` marks rows
that are not executable by construction (`#` or `?` operands, `#` result).
`Unsupported` marks legal rows the library cannot run (unknown operation,
condition or rounding). Only `Executable` rows can pass or fail, and the
summary reports every class, so a claim such as "all executable rows pass"
comes with the number of rows it excludes. Strictness (failing when anything is
unsupported) is a policy of the caller: `RunOptions` records it, and the CLI
applies it to the exit code.

### Traps disabled, conditions compared

A `.decTest` row lists conditions, not traps. Running every operation with an
empty trap set makes `decimal_gda` return the specified default result (for
example a quiet NaN for an invalid operation) and report all raised
conditions, which is exactly what the row states. Comparing the whole set
in both directions catches both missing and spurious `Inexact`, `Rounded`,
`Clamped` and similar conditions.

### Representation-exact comparison

GDA specifies the exponent of every result, so a library that returns the
right value with the wrong exponent is wrong. Comparing with
`compare_total`, or by exact string, makes the cohort, the sign of zero and the
NaN payload part of the test. The only value-level comparison is for
`32#`/`64#`/`128#` results, where the encoding conditions are what the row
tests.

### Directive context resolved once per change

Each row stores the directive record in force on its line. `execute_documents`
converts it to `decimal_gda` contexts only when it differs from the previous
row's record. Conversion is a pure function of the record, so the cache never
changes a result; it removes repeated work in files with thousands of rows
under one context.

### Deterministic sharding

**Problem.** The corpus is large and runs in parallel processes, whose results
must add up to the serial run.

**Choice.** After filtering, rows are numbered $k = 0, 1, \dots, N-1$ in
document order and shard $i$ of $n$ takes $S_i = \{k : k \bmod n = i\}$.
Round-robin assignment spreads files with slow operations (`power`, `ln`)
across shards instead of giving one shard a whole slow file.

## Correctness and invariants

**Partition.** For $n \ge 1$ the sets $S_0, \dots, S_{n-1}$ are pairwise
disjoint and cover $\{0, \dots, N-1\}$, because every $k$ has exactly one
residue modulo $n$. Their sizes are balanced:

$$
|S_i| = \left\lceil \frac{N - i}{n} \right\rceil
\in \left\{ \left\lfloor \frac{N}{n} \right\rfloor,
            \left\lceil \frac{N}{n} \right\rceil \right\}.
$$

**Shard independence.** The disposition and result of a row depend only on
the row (its tokens and its directive record): parsing fixes the record
per row, and the context cache memoizes a pure function. Hence the result of
row $k$ is the same in every shard that contains it and in the serial run, and

$$
\operatorname{merge}(R_0, \dots, R_{n-1}) \text{ has the counters of } R_{\text{serial}},
$$

since `merge` adds every counter and the shards partition the rows
(`total_cases` is the same $N$ in every shard and `merge` keeps it).

**Counter identities.** For every summary,
$\text{selected} = \text{executable} + \text{skipped}$,
$\text{executable} = \text{passed} + \text{failed}$ and
$\text{skipped} = \text{diagnostic} + \text{legacy} + \text{unsupported}$;
they hold because each result is counted in exactly one class by
`internal/conformance`.

**Totality.** Parsing assigns every line to exactly one of: skipped (empty or
comment), directive, row, diagnostic. Execution does not abort on the tokens
of a row: decoding and dispatch failures become a failed result with the
message `"evaluation failed"`. It does abort on a directive context with a
non-positive precision, because the context conversion calls
`@decimal_gda.DecimalContext::new`, which aborts on it; parsing accepts any
integer for `precision`.

**Complexity.** Parsing is linear in the text length. Execution is linear in
the number of rows plus the cost of the decimal operations themselves.

## Alternatives rejected

- **Value-only comparison.** Simpler, but it would accept wrong exponents and
  signs of zero, which the specification and the corpus test deliberately.
- **Subset comparison of conditions** (only listed conditions must be raised).
  It would accept spurious `Inexact` or `Clamped`, a common class of bugs.
- **Executing `#` and `?` rows with ad-hoc meanings.** These rows have no
  scalar meaning; inventing one would make the pass count meaningless.
- **Contiguous shards.** Splitting the row list into blocks is equally
  deterministic but puts whole slow files into one shard.

## Boundaries

- No file system access, globbing or process exit codes: those belong to
  [`cli/gda_expr_cli`](../cli/gda_expr_cli.md) and `tools/`.
- No traps: rows are executed with every trap disabled.
- Operands with more than $\max(64, p)$ significant digits are rounded
  half-even when decoded, so such rows can be rounded twice.
- A `precision` directive of 0 or less aborts execution instead of producing
  a diagnostic or an `Invalid_context` row.
- The `''` escape of quoted decTest strings is not recognized.
- `Legacy` is part of the shared result model but is never assigned by the
  current executor.
- The executor tests `decimal_gda` only; IEEE decimal (`decimal`) has its own
  corpus runner in `tools/`.
