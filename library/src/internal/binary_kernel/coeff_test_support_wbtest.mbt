///|
/// Parses `text` as a BigInt; malformed text aborts.
fn bigint_from_text(text : StringView, radix~ : Int32 = 10) -> BigInt {
  @string.parse_bigint(text, radix~) catch {
    _ => abort("invalid BigInt text")
  }
}

///|
/// The integer of `count` limbs of `words` from `offset`, least significant first.
fn bin_limbs_big(
  words : FixedArray[UInt64],
  offset : Int32,
  count : Int32,
) -> BigInt {
  let mut value = BigInt::from_int(0)
  for index = count - 1; index >= 0; index = index - 1 {
    value = (value << 64) + BigInt::from_uint64(words[offset + index])
  }
  value
}

///|
// oracle: A
// source: the integers 1, 7, 7 2^64 + 1 and 2^128 - 1 written out from their limbs, and the all-zero row
// shares: nothing (BigInt shift and addition of core)
test "bin_limbs_big reads the limbs least significant first" {
  let words : FixedArray[UInt64] = [
    9UL, 1UL, 7UL, 0xffff_ffff_ffff_ffffUL, 0xffff_ffff_ffff_ffffUL,
  ]
  assert_eq(bin_limbs_big(words, 1, 1), BigInt::from_int(1))
  assert_eq(bin_limbs_big(words, 2, 1), BigInt::from_int(7))
  assert_eq(
    bin_limbs_big(words, 1, 2),
    BigInt::from_int(7) * (BigInt::from_int(1) << 64) + BigInt::from_int(1),
  )
  assert_eq(
    bin_limbs_big(words, 3, 2),
    (BigInt::from_int(1) << 128) - BigInt::from_int(1),
  )
  assert_eq(bin_limbs_big(words, 0, 0), BigInt::from_int(0))
}
