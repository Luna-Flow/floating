///|
// The oracle programs of the gates keep their own copy of the library's limits
// (`tools/generate_mpfr_random_oracle.c`, `tools/range_boundary_rows.py`,
// `tools/context_rules.py`, `tools/generate_libmpdec_random.py`): that is what
// keeps them independent of the library. The numbers are therefore written
// out here, once more, and the test fails when the library's constant changes
// without the oracle programs (and this list) changing with it. The Python
// side is tied to the same numbers by `tools/oracle_constants_test.py`.
//
// Oracle (level A): the numbers are written out from the decisions that fix
// them, not read from the library:
// - binary: IEEE 754-2019 3.3 (`emin = 1 - emax`) and 3.7 (the extendable
//   format; NOTE: the implementation limit is a decision of the library: the
//   exponent of the leading bit must fit a 31-bit field, e_max 2^30 - 1, and
//   the largest precision 2^28 keeps every coefficient exponent in `Int32`).
// - decimal: GDA 1.70 page 10 and the decision of the library that the
//   largest precision and exponent of a context are 999,999,999 (the limits of
//   the reference implementation's Context).

///|
test "the library limits equal the numbers written in the oracle programs" {
  assert_eq(@bin_float.binary_implementation_e_max, 1073741823)
  assert_eq(@bin_float.binary_implementation_e_min, -1073741822)
  assert_eq(@bin_float.binary_precision_max, 268435456)
  assert_eq(
    @bin_float.binary_implementation_e_min,
    1 - @bin_float.binary_implementation_e_max,
  )
  assert_eq(@decimal.decimal_implementation_e_max, 999999999)
  assert_eq(@decimal.decimal_implementation_e_min, -999999998)
  assert_eq(@decimal.decimal_precision_max, 999999999)
}
