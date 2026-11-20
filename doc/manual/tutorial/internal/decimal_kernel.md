# internal/decimal_kernel tutorial

The goal of this page is to show maintainers how to use the shared coefficient
kernel when they add or change a decimal operation, and how to keep a change to
it safe for both standards. The package is internal to `Luna-Flow/floating`;
the examples are written for code inside the module and are not compiled by the
manual checker.

| I want to | Use |
| --- | --- |
| compute with exact coefficients in `decimal` or `decimal_gda` | [the `dec_coeff_*` functions](#use-the-kernel-from-a-decimal-package) |
| add an algorithm or a fast path | [change the kernel](#change-the-kernel) |
| tune a threshold | [per-target thresholds](#tune-a-threshold) |
| decide where new code belongs | [kernel or finalizer](#decide-where-new-code-belongs) |
| run the kernel tests | [`just decimal-kernel-ci`](#run-the-tests) |

## Use the kernel from a decimal package

Both packages import the kernel and bring the names they use into scope with
`using`:

```moonbit nocheck
///|
using @decimal_kernel {
  type DecCoeff,
  dec_coeff_div_rem_repr,
  dec_coeff_from_decimal_digits_repr,
}
```

A `Decimal` stores its coefficient as a private `DecCoeff` field, so the type
never appears in the public interface of the package. A typical use builds the
exact quotient and remainder, and leaves the rounding decision to the package:

```moonbit nocheck
///|
fn exact_quotient(numerator : DecCoeff, denominator : DecCoeff) -> (DecCoeff, DecCoeff) {
  // exact integers: no flag, no rounding mode, no context
  dec_coeff_div_rem_repr(numerator, denominator)
}
```

## Decide where new code belongs

Put code in the kernel when it is a function from coefficients (and plain
integers) to coefficients or integers, and when `decimal` and `decimal_gda`
would compute it identically. Keep it in the decimal package when it mentions a
rounding mode, a precision, an exponent range, a flag, a trap, a `Decimal` or a
context, because those are where the two standards differ. The test is simple:
the function must give the same answer if the same integers are fed to it from
either standard. `tools/check_imports.py` enforces the dependency half of the
rule (the kernel cannot import `decimal` or `decimal_gda`).

## Change the kernel

1. Write the change as an exact integer function and keep it free of clauses:
   no `if` on a standard, no hidden state.
2. Add or extend a white-box test in `coeff_kernel_wbtest.mbt` that compares the
   result with `BigInt` at the limb boundaries (9, 18, 19, 27 digits), at the
   threshold lengths of every target, and on operands of nines, powers of ten
   and sparse limbs.
3. Run `just decimal-kernel-ci`, then the package tests and the two gates:
   `just gate decimal 3` and `just gate decimal_gda 3`.
4. Measure both packages. A change that helps one standard and slows the other
   needs a reason in the pull request.

## Tune a threshold

The crossovers between schoolbook, Karatsuba, Toom-3, the NTT, Burnikel–Ziegler
and Newton division live in `coeff_thresholds_native.mbt`, `_llvm`, `_wasm`,
`_wasm_gc` and `_js`; `moon.pkg` selects the file by target. A threshold only
changes which exact algorithm runs. Change it with paired old/new builds on the
target, for both `decimal` and `decimal_gda`, and keep the dispatch tests that
cross every threshold exactly.

## Run the tests

```bash
just decimal-kernel-ci
sh tools/run_moon_clean_exec.sh test library/src/internal/decimal_kernel --target native
```

The `internal/decimal_kernel` tests carry the algorithm cross-checks that used
to be duplicated in the two decimal packages. The decimal packages keep the
tests that need a `Decimal`.
