# differential/interval_mpfr design

## Design goal

Give `interval` an oracle from outside the repository at the ends of the exponent range, where its tests had only `Binary` in a wide context to compare with, and make the stage independent of the code it checks, so that a defect in `interval`, in `binary` or in a reader of the library cannot cancel against itself.

## Mathematical background

For an operation $f$ that is monotone or multi-affine in each argument, the tightest interval is the hull of the values at the corners of the operand box. With $\mathrm{rnd}_\downarrow$ and $\mathrm{rnd}_\uparrow$ the directed roundings to $p$ bits in the format of `binary` (exponent range $[e_{\min}, e_{\max}]$ with gradual underflow),

$$
\text{lower} = \min_{c}\ \mathrm{rnd}_\downarrow\bigl(f(c)\bigr),
\qquad
\text{upper} = \max_{c}\ \mathrm{rnd}_\uparrow\bigl(f(c)\bigr),
$$

over the corners $c$ (four for `mul` and `div`, eight for `fma`, the two ends for `add`, `sub` and `sqrt`; `sqr` of an interval around zero has the lower bound 0). Rounding is monotone, so the rounded minimum of the corners is the minimum of the rounded corners. IEEE 1788-2015 12.10.2 requires this tightest result for the basic operations of Table 9.1, so the bounds must be equal.

## Design decisions

### Two oracles that share nothing with the library

`tools/interval_mpfr_oracle.c` evaluates the corners with MPFR (`mpfr_add`, `mpfr_mul`, `mpfr_fma`, ... with `MPFR_RNDD` and `MPFR_RNDU`). The exponent range of `binary` is set in MPFR as `tools/generate_mpfr_random_oracle.c` does for the binary gate: MPFR writes a value as $0.1xxx \times 2^e$, one binade above `binary`'s leading-bit exponent at both ends, so the range is $[e_{\min} - p + 2,\ e_{\max} + 1]$, and a result whose MPFR exponent is at most $e_{\min}$ goes through `mpfr_subnormalize` with the ternary value of the first rounding (exact for the directed modes). The oracle in `tools/interval_diff.py` computes the same corners with Python integers and a directed rounding written from the definition; it needs nothing but CPython, decides every arithmetic row (a far addend, more than 4,000 bits below the other, only decides the side of the rounding, so the exact sum is the larger addend plus a remainder smaller than one unit of it scaled to $p + 2$ bits; a quotient or a root keeps its remainder as a sticky bit) and is the required oracle of the gate stage. MPFR is the second oracle, run when its headers are found, and the two must agree on every arithmetic row. The report names the oracles that ran and the rows only MPFR decides (`exp`, `ln`) as not checked when it did not. `mpfr_sqrt` of MPFR 4.2.2 has a known defect, so a root is checked with an exact product and the row is undecided if the check fails.

### Canonical text, no library reader or writer

The oracle prints `0b<odd integer>p<exponent>`, `inf`, `-inf`, `0`, `-0`; the test builds the same text from the accessors of the value (class, sign, coefficient, exponent), not from `to_hex`. The operands are compared too: the oracle echoes each operand bound after the outward rounding to the precision, and the test compares it with the bound the library holds after `from_hex` and `from_bounds`, so a misreading cannot produce a matching wrong result. The two zeros are one number in the set-based flavour and compare equal.

### `exp` and `ln` must enclose, not be equal

IEEE 1788-2015 12.10.2 requires only a valid result for `exp` and `ln` (and says it should be accurate), so the bounds may differ from the tightest ones. The test requires that the library result encloses the oracle's (the oracle's bounds are read from the hexadecimal text the oracle prints) and that each bound is at most 1,024 units of the last place of the oracle's bound outside it; an infinite or zero oracle bound must be met exactly. A result that encloses but is wider is reported as a failing row with that reason (the shape of issue 569). `exp` and `ln` have no second oracle: MPFR is the only one.

### Generated rows are checked by the oracle's flags

Rows that aim at a band (overflow threshold, subnormal band) are built from integer mantissa arithmetic with the target product, quotient or square written as an integer and an exponent, never as an integer of $2^{2^{30}}$. Whether a class reached its band is not trusted to the generator: the oracle reports overflow, a subnormal result or operand, and underflow to zero, and a class without any such row is an error.

## Correctness and invariants

- A row id fixes its operands: every (operation, class, precision) cell has its own seeded stream.
- Every row is legal by construction and checked on creation (lower bound not above upper, no zero in a divisor, a non-negative operand of `sqrt`).
- A known difference needs an issue number; a listed row that agrees, or a new difference, fails the run.
- The mutation of one directed rounding in the C oracle is caught twice: by the cross-check against the integer oracle and by the comparison with the library.

## Alternatives rejected

- **`Binary` in a wide context as the oracle.** It is the code the interval is built on, and its own tests at the range ends are equivalence tests.
- **MPFI as the oracle of this stage.** MPFI has no subnormal numbers and no range narrower than MPFR's; the MPFI columns belong to the timed cells, where they compare like with like.
- **Random operands only.** The defects of the range ends need operands aimed at them; the classes are built from the targets.

## Boundaries

- The stage covers `add`, `sub`, `mul`, `div`, `sqr`, `sqrt`, `fma`, `exp` and `ln` at 53, 128 and 512 bits (`exp` at the overflow threshold also at 117, 146, 175 and 292 bits); the other elementary functions and the reverse functions have their own rows.
- MPFR and the GMP headers are needed only for the second oracle and for `exp` and `ln`; the stage is the last stage of `just gate interval` (`tools/run_ci.py`) and is not part of `just pr`.
- The two oracles share the correctness of the standard definition of directed rounding; MPFR is the one implementation used for the C side.
