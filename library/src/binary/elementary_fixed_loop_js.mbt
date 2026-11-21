///|
/// The loop of `binary_ln_unit_fixed_bounds` after `Z` and `Q` are known: the sum
/// of the terms `T(k) = floor(P(k) / (2k + 1))` with `P(0) = Z`, `P(k) =
/// floor(P(k-1) Q / 2^F)`, stopping at the first `P(index) < 2^6`; returns the
/// sum (without `P(index)`) and `index`, or `None` after 10000 terms. This is
/// the form on the JS target (a host `BigInt` coefficient has no limb rows); the
/// other targets run `binary_ln_artanh_loop` of `elementary_fixed_loop_nonjs.mbt`,
/// which computes the same integers.
fn binary_ln_artanh_loop(
  z : Coeff,
  square : Coeff,
  fractional : Int32,
) -> (Coeff, Int32)? {
  let stop = Coeff::one().shift_left(6)
  let mut power = z
  let mut sum = z
  let mut index = 0
  while index < 10000 {
    index += 1
    power = power.mul(square).shift_right(fractional)
    if power.compare(stop) < 0 {
      return Some((sum, index))
    }
    let divisor = Coeff::from_uint64((2 * index + 1).to_uint64())
    sum = sum.add(power.div_rem_checked(divisor).unwrap().0)
  }
  None
}
