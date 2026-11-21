///|
/// The canonical text of a `BinFloat` bound, the form `tools/mpfr_ours.h`
/// prints: `nan`, `inf`, `-inf`, `0`, `-0`, or `[-]0b<odd integer in binary>p<exponent>`.
/// Written from the accessors of the value (class, sign, coefficient, exponent)
/// and not through `to_hex`, so that the writer of the library is not in the
/// comparison either.
fn canonical_bound(x : @binary.BinFloat) -> String {
  let negative = x.is_negative()
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
test "canonical_bound: the texts tools/mpfr_ours.h prints" {
  let p = 8
  assert_eq(
    canonical_bound(@binary.BinFloat::from_double(1.5, precision=p)),
    "0b11p-1",
  )
  assert_eq(
    canonical_bound(@binary.BinFloat::from_double(-0.375, precision=p)),
    "-0b11p-3",
  )
  assert_eq(
    canonical_bound(@binary.BinFloat::from_double(8.0, precision=p)),
    "0b1p3",
  )
  assert_eq(canonical_bound(@binary.BinFloat::zero(precision=p)), "0")
  assert_eq(
    canonical_bound(@binary.BinFloat::from_hex("-0x0p0", p).unwrap()),
    "-0",
  )
  assert_eq(
    canonical_bound(@binary.BinFloat::inf(Positive, precision=p)),
    "inf",
  )
  assert_eq(
    canonical_bound(@binary.BinFloat::inf(Negative, precision=p)),
    "-inf",
  )
  assert_eq(canonical_bound(@binary.BinFloat::nan(precision=p)), "nan")
}
