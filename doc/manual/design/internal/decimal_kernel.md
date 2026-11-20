# internal/decimal_kernel design

## Design goal

`decimal` and `decimal_gda` implement two different standards on top of the
same arithmetic: nonnegative integers in decimal digits. The integer part
should exist once, so that a fix or a measurement helps both, while nothing of
either standard leaks into it. The package therefore contains only functions
from integers to integers.

## Mathematical background

A coefficient $c \ge 0$ is stored in base $B = 10^{9}$, the largest power of
ten below $2^{30}$, so a limb product is below $B^{2} = 10^{18} < 2^{60}$ and
fits a `UInt64` together with carries. Values below $10^{18}$ (two limbs) are
kept as one `UInt64`. Digit counts, trailing zeros, the half-unit comparison
and the last-digit test of `ZeroFiveUp` are then limb operations; no
binary-to-decimal conversion exists.

Every operation computes an exact result:

- $\operatorname{add}(a,b) = a + b$, $\operatorname{sub}(a,b) = a - b$ for
  $a \ge b$, $\operatorname{mul}(a,b) = ab$;
- $\operatorname{divrem}(a,b) = (q,r)$ with $a = qb + r$ and $0 \le r < b$;
- $\operatorname{shift}(a,k) = a\cdot 10^{k}$ and
  $\operatorname{divpow10}(a,k) = (\lfloor a/10^{k}\rfloor,\; a \bmod 10^{k} \ne 0,\; \operatorname{sign}(2(a \bmod 10^{k}) - 10^{k}))$,
  which is everything a rounding decision needs;
- $\operatorname{gcd}$, the multiplicity of a unit factor and exact division by
  a unit.

Because each result is determined by the mathematical definition, the algorithm
chosen by the dispatcher (schoolbook, Karatsuba, Toom-3, a two-prime NTT,
Knuth's Algorithm D, Burnikel–Ziegler, Newton reciprocal division) cannot
change a value. The dispatch is performance policy.

### The NTT bound

The NTT uses base-$10^5$ digits and the primes $p_1 = 998\,244\,353$ and
$p_2 = 754\,974\,721$, so $p_1 p_2 = 753\,649\,251\,896\,000\,513$. A
convolution coefficient is a sum of at most $m = \min(n_a, n_b)$ products of
digits at most $99\,999$, hence at most $m\cdot 99\,999^{2}$, and the Chinese
remainder theorem recovers it exactly when that is below $p_1p_2$, that is for
$m < 75\,366\,432$. Both primes have $2^{23}$-th roots of unity, so the
transform length is at most $2^{23}$ and $m \le 2^{22}$:
$2^{22}\cdot 99\,999^{2} = 41\,942\,201\,143\,394\,304 < p_1 p_2$. The bound
holds for every length the transform accepts, and `dec_coeff_ntt_limits_fit`
checks it before each use. (`decimal` used base-$10^4$ digits before the
kernels were shared; the bound $2^{22}\cdot 9\,999^{2}$ was also satisfied, and
the product is the same integer either way.)

## Design decisions

### One kernel, two representations merged

The two packages had diverged. `decimal_gda` stored `Small(UInt64)` and had
small-value fast paths, a numerator-aware division dispatch and an
allocation-free scaled comparison; `decimal` stored an inline `UInt32`, had
`gcd`, `mod`, `shift_power10_mod` and a whole-limb mode in `trim`. The shared
kernel is the union, built on the `Small(UInt64)` representation, because the
fast paths are pure integer facts. The functions that only one side had are
kept (they are exact integer functions too). The `trim` whole-limb mode counts
trailing zeros per limb instead of per digit and returns the same count as the
digit loop; `dec_coeff_count_factor_unit_repr` returns early when the lowest
limb is not divisible by 2 or 5 (the base is divisible by both, so the lowest
limb decides), which is cheaper than the batched attempt for the common case.

### Rounding decisions as pure functions

A rounding decision is a function of a coefficient and the digits that were
discarded: given $q$, the remainder $r$ with $0 \le r < d$, the sign and the
direction, the kept magnitude is incremented when

$$
\begin{cases}
\text{never} & \text{Down},\\
\text{always (if } r > 0) & \text{Up},\\
\operatorname{sign} = + & \text{Ceiling},\\
\operatorname{sign} = - & \text{Floor},\\
2r > d \lor (2r = d \land q \text{ odd}) & \text{HalfEven},\\
2r \ge d & \text{HalfUp},\\
2r > d & \text{HalfDown},\\
q \bmod 10 \in \{0, 5\} & \text{ZeroFiveUp}.
\end{cases}
$$

The kernel computes this from `dec_coeff_div_pow10_round_info_repr` or a
division, in a `DecCoeffRounding` enum that carries the direction only. What the
direction is applied to (the precision, the exponent range, the tininess rule,
the flags raised by the discarded digits) is decided by the finalizer of each
package, which converts its own rounding mode with one total match. The kernel
therefore needs neither package's mode, context nor flags type.

### What stays out

Nothing that depends on a standard moves here: rounding modes, precision,
exponent range, the finalizer, flags, traps, the `Decimal` type, the DPD and
BID codecs. The design page of `decimal_gda` explains why those must not be
shared. A function belongs in the kernel only if it would be correct, with the
same meaning, in either standard.

### Public types, internal package

`DecCoeff` and `DecCoeffRounding` are `pub(all)` so that the two packages can
pattern-match the `Small` case in their own fast paths without a call per
access; `SignedDecCoeff` is `pub`, so its fields can be read but only this
package builds one. The algorithm enums, the scratch types and the helpers
that no other package uses are private: the package keeps public only what
`decimal`, `decimal_gda` or their tests name. Visibility is also bounded by the
package itself: `internal/` makes it unimportable outside `Luna-Flow/floating`,
and no public signature of `decimal` or `decimal_gda` mentions the types.

### Option-free hot paths

`dec_coeff_small_value` returns an `Option`, which allocates for a small
value. Functions on the hot path of the `decimal` greatest-common-divisor loop
(`dec_coeff_mod_repr`) match the constructors directly instead. A paired A/B of
`decimal` division at 34 and 100 digits showed the allocation; matching
removed it.

### Digit counts, accumulators and exact quotients

`dec_coeff_small_digits` counts the digits of a one-word value with the
leading-zero count (`floor(bits * 1233 / 4096)` is the digit count or one
less) and one comparison with a power of ten; `value | 1` maps zero to one
digit and never changes the count of another value. Both packages use it, as
`digits10` of every `Small` coefficient. `dec_coeff_from_unit_accumulator`
trims leading zero limbs and truncates the buffer in one step and does not scan
the limbs for values at or above the base: every producer writes limbs below
the base, which the white-box test "unit accumulator producers write limbs
below the base" checks over shifts, sums, products and quotients. A division
that must also say whether the exact quotient has a finite decimal expansion
uses `dec_coeff_round_div_expansion`: with $d = 2^a 5^b u$, $u$ prime to 10,
the expansion of $n/d$ is finite exactly when $u \mid n$, and as 10 is
invertible modulo $u$ that is equivalent to $u$ dividing the remainder of
$n\,10^k$ by $d$, so the one division that produces the quotient also decides
it.

### Integer square root

`dec_coeff_integer_sqrt_rem_repr` returns the floor root $s$ of $n$ and the
remainder $n - s^2$. A value below $10^{18}$ takes the hardware root of the
nearest double, which is within one of the answer, and two comparisons with
exact word products settle it. A longer value of $D$ digits is split as
$n = h\,10^{2t} + l$ with $t \approx D/4$ and $0 \le l < 10^{2t}$. The root
$s_h$ of $h$ comes from the same function one level down, and
$x_0 = (s_h + 1)\,10^{t}$ never lies below $s$: $n < (h+1)\,10^{2t}$ and
$h + 1 \le (s_h+1)^2$. Newton's step
$x \mapsto \lfloor (x + \lfloor n/x \rfloor)/2 \rfloor$ started at or above $s$
decreases to $s$ and never falls below it, so the start needs no estimate and
the working size doubles from the bottom of the recursion. The earlier version
began at a power of ten and ran every step at full size, about $\log_2 D + 2$
divisions of a $D$-digit number. The division of each step also ends the loop:
for $x \ge s$ the quotient $q = \lfloor n/x \rfloor$ reaches $x$ exactly when
$x = s$, and then $n = xq + r$ gives the remainder $r + x(q - x)$ with
$q - x \in \{0, 1, 2\}$ (because $n < (x+1)^2$), so the squaring that the
earlier version needed for the remainder is gone. The pair $(s, n - s^2)$ is
unique, so no caller can observe the change; the white-box test compares it bit
for bit with the previous implementation, kept in the test file, on random
operands of 1 to 112 limbs, perfect squares and their neighbours, and powers of
ten.

### Rounding a limb coefficient in one pass

`dec_coeff_round_div_pow10` shifts a coefficient of $D$ digits right by $k$
digits and rounds. Write $k = 9u + c$. The rounding digit is the digit at
position $k - 1$ and the sticky information is whether anything below it is
nonzero; both are read from limb $\lfloor (k-1)/9 \rfloor$ and, only while that
limb's lower part is zero, from the limbs below it (the scan ends at the first
nonzero limb). Limb $j$ of the quotient is then
$\lfloor a_{u+j} / 10^{c} \rfloor + (a_{u+j+1} \bmod 10^{c})\cdot 10^{9-c}$,
one division by $10^{c}$ per source limb, written to a new array of exactly
$\lceil (D-k)/9 \rceil$ limbs, so that no trimming and no digit count is
needed afterwards. The increment is applied to that array in place: it carries
from limb 0 up to the first limb that is not $10^{9}-1$, and appends a limb only
if every limb carried. The digit count of the result is taken from its top
limb. The earlier version copied the coefficient, shifted the copy, trimmed it
and counted its digits, scanned the source again for the rounding digits, and
added the unit through a second copy, a pass and a second digit count: four
allocations and about five passes against one allocation (plus the `Limbs`
box) and one pass.

`dec_coeff_round_div_pow10_owned` is the same function for a caller that owns
the limb array: the shift writes behind its own reads (limb $j$ of the result
is stored after limb $j+1$ of the source was loaded, and $j \le u + j$), so the
array is rounded in place and truncated, and becomes the limbs of the result.
Values of two limbs or fewer are always below $10^{18}$ and are `Small`. The
white-box test compares both entries with the previous implementation, kept
in the test file, bit for bit.

## Correctness and invariants

- **Canonical form.** A `Limbs` value has no leading zero limb and is at least
  $10^{18}$; a smaller value is `Small`. Equal integers therefore have equal
  representations, and `DecCoeff::to_string` is the plain decimal string.
- **Persistence.** No operation mutates the limbs of an operand.
- **Totality inside the contract.** A violated precondition aborts; it is never
  mapped to a value.
- **Exactness.** All results equal the `BigInt` result. The white-box tests
  compare with `BigInt` at limb boundaries, at the threshold of every target and
  for forced algorithms on nines, powers of ten and sparse operands.

## Trade-offs and limitations

Sharing means a performance change hits both standards; every change is
measured on both. The kernel is not a general bignum: it has no negative
numbers except `SignedDecCoeff` for intermediate values, and no radix other
than $10^{9}$.

## References

D. E. Knuth, *The Art of Computer Programming*, vol. 2, 3rd ed., §4.3.1;
C. Burnikel and J. Ziegler, "Fast recursive division", MPI-I-98-1-022, 1998;
R. Brent and P. Zimmermann, *Modern Computer Arithmetic*, Cambridge 2010,
§1.3–1.4 and §2.4.
