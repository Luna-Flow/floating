///|
/// The canonical text of a `Binary` bound, the form `tools/mpfr_ours.h`
/// prints: `nan`, `inf`, `-inf`, `0`, `-0`, or `[-]0b<odd integer in binary>p<exponent>`.
/// Written from the accessors of the value (class, sign, coefficient, exponent)
/// and not through `to_hex`, so that the writer of the library is not in the
/// comparison either.
fn canonical_bound(x : @binary.Binary) -> String {
  let negative = x.is_sign_minus()
  match x.classify() {
    NaN => "nan"
    Infinity => if negative { "-inf" } else { "inf" }
    Finite =>
      if x.is_zero() {
        if negative {
          "-0"
        } else {
          "0"
        }
      } else {
        let bits = x.coefficient().to_radix_string(2)
        let chars : Array[Char] = []
        for c in bits {
          chars.push(c)
        }
        let mut last = chars.length()
        while last > 1 && chars[last - 1] == '0' {
          last -= 1
        }
        let trailing = chars.length() - last
        let digits = StringBuilder()
        for i in 0..<last {
          digits.write_char(chars[i])
        }
        (if negative { "-" } else { "" }) +
        "0b" +
        digits.to_string() +
        "p" +
        (x.exponent2().to_int64() + trailing.to_int64()).to_string()
      }
  }
}

///|
// Oracle: level A (expected texts written out by hand).
// oracle: A
// source: expected texts written out by hand: 3/2 is 0b11p-1, -3/8 is -0b11p-3, 8 is 0b1p3, the signs of zero and the
//   specials; they are the form of the C tool tools/mpfr_ours.h
// shares: Binary::from_double, zero, from_hex, inf and nan (build the bounds that are printed)
test "canonical_bound: the texts tools/mpfr_ours.h prints" {
  let p = 8
  assert_eq(
    canonical_bound(@binary.Binary::from_double(1.5, precision=p)),
    "0b11p-1",
  )
  assert_eq(
    canonical_bound(@binary.Binary::from_double(-0.375, precision=p)),
    "-0b11p-3",
  )
  assert_eq(
    canonical_bound(@binary.Binary::from_double(8.0, precision=p)),
    "0b1p3",
  )
  assert_eq(canonical_bound(@binary.Binary::zero(precision=p)), "0")
  assert_eq(
    canonical_bound(@binary.Binary::from_hex("-0x0p0", p).unwrap()),
    "-0",
  )
  assert_eq(canonical_bound(@binary.Binary::inf(precision=p)), "inf")
  assert_eq(
    canonical_bound(@binary.Binary::inf(negative=true, precision=p)),
    "-inf",
  )
  assert_eq(canonical_bound(@binary.Binary::nan(precision=p)), "nan")
}
