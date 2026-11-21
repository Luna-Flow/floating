# internal/binary_kernel tutorial

The goal of this page is to show maintainers how to use the coefficient kernel
when they add or change a binary operation, and how to keep a change to it safe
for every target. The package is internal to `Luna-Flow/floating`; the examples
are written for code inside the module and are not compiled by the manual
checker.

| I want to | Use |
| --- | --- |
| compute with exact coefficients in `binary` | [the `Coeff` methods](#use-the-kernel-from-the-binary-package) |
| add an algorithm or a fast path | [change the kernel](#change-the-kernel) |
| tune a threshold | [per-target thresholds](#tune-a-threshold) |
| decide where new code belongs | [kernel or `binary`](#decide-where-new-code-belongs) |
| run the kernel tests | [`just bin-kernel-ci`](#run-the-tests) |

## Use the kernel from the `binary` package

`binary` imports the kernel and brings the names it uses into scope with
`using` (in `kernel_imports.mbt`, and `kernel_imports_nonjs.mbt` for the names
that exist only where a coefficient has 64-bit limbs):

```moonbit nocheck
///|
using @binary_kernel { type Coeff, bin_coeff_short_div_rem }
```

A `Binary` stores its coefficient as a private `Coeff` field. The public type
`BinCoeff` is a newtype over it (`value.0` unwraps it and `BinCoeff(c)` wraps a
result), so the kernel type shows in a public interface only as the field of
`BinCoeff`, which is opaque outside the module, and the wrapping costs neither
an allocation nor a call. A typical
use computes the exact quotient and remainder and leaves rounding to
`binary`:

```moonbit nocheck
///|
fn exact_quotient(numerator : Coeff, denominator : Coeff) -> (Coeff, Coeff) {
  // exact integers: no flag, no rounding mode, no context
  bin_coeff_short_div_rem(numerator, denominator)
}
```

## Decide where new code belongs

Put code in the kernel when it is a function from coefficients (and plain
integers) to coefficients or integers. Keep it in `binary` when it mentions a
rounding mode, a precision, an exponent, a class, a flag or a `Binary`. The
test is simple: the function must give the same answer for the same integers
whoever calls it. `tools/check_imports.py` enforces the dependency half of the
rule: the kernel imports nothing of this module.

## Change the kernel

1. Write the change as an exact integer function.
2. Add or extend a white-box test next to the others in the package that
   compares the result with `BigInt` at the limb boundaries (64, 128 and 192
   bits), at the threshold lengths of every target, and on operands of ones,
   powers of two and sparse limbs.
3. Run `just bin-kernel-ci`, then `just gate binary 3` and `just gate interval 3`.
4. Measure retired instructions with the benchmark rows of the pull request
   against the previous build; a change that helps one operation and slows
   another needs a reason in the pull request.

## Tune a threshold

The crossovers between schoolbook, Karatsuba, Toom-3, the NTT, Knuth's division
and Burnikel-Ziegler live in `coeff_thresholds_native.mbt`, `_llvm`, `_wasm`
and `_wasm_gc`; `moon.pkg` selects the file by target. JavaScript has no
kernel: its `Coeff` is a host `bigint`. A threshold only changes which exact
algorithm runs. Change it with paired old and new builds on the target, and keep
the dispatch tests that cross every threshold exactly. The cutoffs of the
elementary functions (`binary_exp_burst_min_precision` and its siblings) are
thresholds of `binary`, in `elementary_thresholds_<target>.mbt`.

## Run the tests

```bash
just bin-kernel-ci
sh tools/run_moon_clean_exec.sh test library/src/internal/binary_kernel --target native
```

The `internal/binary_kernel` tests carry the algorithm cross-checks, the
dispatch tests and the regression digests that used to live in `binary`.
`binary` keeps the tests that need a `Binary`.
