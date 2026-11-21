///|
/// Working precisions from which `pi`, `ln 2` and `ln 10` are computed by
/// binary splitting; below it the artanh and arctangent series of
/// `elementary_certified.mbt` run. The two paths return enclosures of the same
/// number, so the choice only moves time.
let binary_constants_split_min_precision : Int32 = 64

///|
/// `sum_{j < terms} 1 / ((2j+1) K^j)` as `t / q`: the factors
/// `p(j) = 2j - 1` and `q(j) = (2j + 1) K` telescope to `1 / ((2j+1) K^j)`.
/// `artanh(1 / k) = (1 / k) * sum` with `K = k^2`.
fn split_artanh_state(from : Int32, to : Int32, square : Coeff) -> SplitState {
  if to - from == 1 {
    if from == 0 {
      return {
        p: Coeff::one(),
        q: Coeff::one(),
        q_shift: 0,
        t_negative: false,
        t: Coeff::one(),
      }
    }
    let odd = from.to_uint64() * 2UL
    let p = Coeff::from_uint64(odd - 1UL)
    return {
      p,
      q: Coeff::from_uint64(odd + 1UL).mul(square),
      q_shift: 0,
      t_negative: false,
      t: p,
    }
  }
  let middle = from + (to - from) / 2
  split_combine(
    split_artanh_state(from, middle, square),
    split_artanh_state(middle, to, square),
  )
}

///|
/// Directed enclosure `[low, high]` of `sum_{j >= 0} 1 / ((2j+1) K^j)` with
/// `K = k^2`, evaluated to `precision` bits. The partial sum over `terms` terms
/// is `t / q` exactly. With `K^terms >= 2^(precision + 9)` the first omitted
/// term is at most `2^-(precision + 9)` and the omitted terms, which are
/// positive and shrink at least by `1 / K <= 1/4` from one to the next, sum to
/// less than twice that, so `high = t / q + 2^-(precision + 8)` rounded up.
/// `reduce_terms` removes terms and exists only so a test can show that the
/// count matters (it makes the enclosure wrong).
fn split_artanh_sum_bounds(
  k : Int32,
  precision : Int32,
  reduce_terms~ : Int32 = 0,
) -> (Binary, Binary) {
  let square = Coeff::from_uint64(
    (k.to_int64() * k.to_int64()).reinterpret_as_uint64(),
  )
  let bits = square.bit_length() - 1
  let terms = Int32::max(
    1,
    (precision + 9 + bits - 1) / bits + 1 - reduce_terms,
  )
  let state = split_artanh_state(0, terms, square)
  let downward = binary_working_context(precision, rounding=RoundTowardNegative)
  let upward = binary_working_context(precision, rounding=RoundTowardPositive)
  let numerator = Binary::make_coeff(
    state.t,
    0,
    Int32::max(1, state.t.bit_length()),
  )
  let denominator = Binary::make_coeff(
    state.q,
    0,
    Int32::max(1, state.q.bit_length()),
  )
  let low = numerator.div_ctx(denominator, downward).0
  let tail = Binary::make_coeff(Coeff::one(), -(precision + 8), 1)
  let high = numerator.div_ctx(denominator, upward).0.add_ctx(tail, upward).0
  (low, high)
}

///|
/// Directed enclosure of `coefficient * artanh(1 / k)`.
fn split_scaled_artanh_bounds(
  coefficient : Int32,
  k : Int32,
  precision : Int32,
  reduce_terms~ : Int32 = 0,
) -> (Binary, Binary) {
  let downward = binary_working_context(precision, rounding=RoundTowardNegative)
  let upward = binary_working_context(precision, rounding=RoundTowardPositive)
  let (low, high) = split_artanh_sum_bounds(k, precision, reduce_terms~)
  let scale = Binary::from_int_raw(coefficient, precision~)
  let divisor = Binary::from_int_raw(k, precision~)
  (
    low.mul_ctx(scale, downward).0.div_ctx(divisor, downward).0,
    high.mul_ctx(scale, upward).0.div_ctx(divisor, upward).0,
  )
}

///|
/// Certified enclosure of `ln 2` at `work_precision` by the Machin-type
/// formula `ln 2 = 18 artanh(1/26) - 2 artanh(1/4801) + 8 artanh(1/8749)`
/// and binary splitting of the three series. The enclosure is computed with 16
/// extra bits and then rounded outward to `work_precision` bits.
fn binary_ln2_split_bounds(
  work_precision : Int32,
  reduce_terms~ : Int32 = 0,
) -> (Binary, Binary) {
  let precision = work_precision + 16
  let downward = binary_working_context(precision, rounding=RoundTowardNegative)
  let upward = binary_working_context(precision, rounding=RoundTowardPositive)
  let first = split_scaled_artanh_bounds(18, 26, precision, reduce_terms~)
  let second = split_scaled_artanh_bounds(2, 4801, precision, reduce_terms~)
  let third = split_scaled_artanh_bounds(8, 8749, precision, reduce_terms~)
  let low = first.0.sub_ctx(second.1, downward).0.add_ctx(third.0, downward).0
  let high = first.1.sub_ctx(second.0, upward).0.add_ctx(third.1, upward).0
  (
    low.with_precision_raw(
      work_precision,
      BinaryRoundingMode::RoundTowardNegative,
    ),
    high.with_precision_raw(
      work_precision,
      BinaryRoundingMode::RoundTowardPositive,
    ),
  )
}

///|
/// Certified enclosure of `ln 10 = 3 ln 2 + 2 artanh(1/9)` at `work_precision`.
fn binary_ln10_split_bounds(
  work_precision : Int32,
  reduce_terms~ : Int32 = 0,
) -> (Binary, Binary)? {
  let precision = work_precision + 16
  guard binary_ln2_bounds(work_precision) is Some((ln2_low, ln2_high)) else {
    return None
  }
  let downward = binary_working_context(precision, rounding=RoundTowardNegative)
  let upward = binary_working_context(precision, rounding=RoundTowardPositive)
  let three = Binary::from_int_raw(3, precision~)
  let part = split_scaled_artanh_bounds(2, 9, precision, reduce_terms~)
  let low = ln2_low.mul_ctx(three, downward).0.add_ctx(part.0, downward).0
  let high = ln2_high.mul_ctx(three, upward).0.add_ctx(part.1, upward).0
  Some(
    (
      low.with_precision_raw(
        work_precision,
        BinaryRoundingMode::RoundTowardNegative,
      ),
      high.with_precision_raw(
        work_precision,
        BinaryRoundingMode::RoundTowardPositive,
      ),
    ),
  )
}

///|
let chudnovsky_a : UInt64 = 13591409UL

///|
let chudnovsky_b : UInt64 = 545140134UL

///|
/// `640320^3 / 24`.
let chudnovsky_c3_over_24 : UInt64 = 10939058860032000UL

///|
/// Binary splitting state of the Chudnovsky series
/// `S = sum_k (-1)^k (6k)! (A + B k) / ((3k)! (k!)^3 640320^(3k))` on `[from, to)`,
/// in the usual form with `p(k) = (6k-5)(2k-1)(6k-1)`, `q(k) = k^3 640320^3 / 24`
/// and `a(k) = (A + B k) (-1)^k`; `p` and `q` are positive and the sign lives in
/// `t`. Then `S_N = t / q` over `[0, N)`.
fn split_chudnovsky_state(from : Int32, to : Int32) -> SplitState {
  if to - from == 1 {
    if from == 0 {
      return {
        p: Coeff::one(),
        q: Coeff::one(),
        q_shift: 0,
        t_negative: false,
        t: Coeff::from_uint64(chudnovsky_a),
      }
    }
    let k = from.to_uint64()
    let p = Coeff::from_uint64(6UL * k - 5UL)
      .mul(Coeff::from_uint64(2UL * k - 1UL))
      .mul(Coeff::from_uint64(6UL * k - 1UL))
    let k_coeff = Coeff::from_uint64(k)
    let q = k_coeff
      .mul(k_coeff)
      .mul(k_coeff)
      .mul(Coeff::from_uint64(chudnovsky_c3_over_24))
    let linear = Coeff::from_uint64(chudnovsky_a + chudnovsky_b * k)
    return { p, q, q_shift: 0, t_negative: from % 2 == 1, t: p.mul(linear), }
  }
  let middle = from + (to - from) / 2
  split_combine(
    split_chudnovsky_state(from, middle),
    split_chudnovsky_state(middle, to),
  )
}

///|
/// Certified enclosure of `pi` at `work_precision` by the Chudnovsky series,
/// `pi = 426880 sqrt(10005) / S`.
///
/// The factorial part of the ratio of consecutive terms is
/// `8 (6k+1)(6k+3)(6k+5) / (k+1)^3 <= 1728`, the linear factor grows by at most
/// 41.11 from `k = 0` to `1` and by less than 2 afterwards, and
/// `640320^3 > 2^57.8`; so every ratio is below `2^-41.7` (`k = 0`) or
/// `2^-46.1`, the terms decrease in size and alternate in sign, and the
/// first term is below `2^24`. Hence the sum of the omitted terms from index
/// `N` on is at most the size of term `N`, below `2^(-17 - 46 (N - 1))`, which
/// is at most `2^-(F + 4)` for `N = F / 46 + 3` (`F` the internal precision).
/// With `t / q` the exact partial sum over `N` terms, `S` lies in
/// `[(t - e) / q, (t + e) / q]` for the integer `e = q / 2^(F+4) + 1`, and
/// `sqrt(10005)` is enclosed by directed square roots, so the division of
/// the directed bounds encloses `pi`. `reduce_terms` is the test hook of the
/// artanh bounds.
fn binary_pi_split_bounds(
  work_precision : Int32,
  reduce_terms~ : Int32 = 0,
) -> (Binary, Binary)? {
  let precision = work_precision + 16
  let terms = Int32::max(1, precision / 46 + 3 - reduce_terms)
  let state = split_chudnovsky_state(0, terms)
  guard !state.t_negative else { return None }
  let slack = state.q.shift_right(precision + 4).add(Coeff::one())
  guard state.t.compare(slack) > 0 else { return None }
  let t_low = state.t.sub_checked(slack).unwrap()
  let t_high = state.t.add(slack)
  let downward = binary_working_context(precision, rounding=RoundTowardNegative)
  let upward = binary_working_context(precision, rounding=RoundTowardPositive)
  let radicand = Binary::from_int_raw(10005, precision~)
  let root_low = radicand.sqrt_ctx(downward).0
  let root_high = radicand.sqrt_ctx(upward).0
  let numerator_scale = Binary::make_coeff(
    state.q.mul(Coeff::from_uint64(426880UL)),
    0,
    Int32::max(1, state.q.bit_length() + 20),
  )
  let low = root_low.mul_ctx(numerator_scale, downward).0.div_ctx(
      Binary::make_coeff(t_high, 0, Int32::max(1, t_high.bit_length())),
      downward,
    ).0
  let high = root_high.mul_ctx(numerator_scale, upward).0.div_ctx(
      Binary::make_coeff(t_low, 0, Int32::max(1, t_low.bit_length())),
      upward,
    ).0
  Some(
    (
      low.with_precision_raw(
        work_precision,
        BinaryRoundingMode::RoundTowardNegative,
      ),
      high.with_precision_raw(
        work_precision,
        BinaryRoundingMode::RoundTowardPositive,
      ),
    ),
  )
}

///|
fn binary_ln2_compute(work_precision : Int32) -> (Binary, Binary)? {
  if work_precision >= binary_constants_split_min_precision {
    Some(binary_ln2_split_bounds(work_precision))
  } else {
    binary_ln2_series_compute(work_precision)
  }
}

///|
fn binary_ln10_bounds_compute(work_precision : Int32) -> (Binary, Binary)? {
  if work_precision >= binary_constants_split_min_precision {
    binary_ln10_split_bounds(work_precision)
  } else {
    binary_ln10_series_compute(work_precision)
  }
}

///|
fn binary_pi_bounds_compute(work_precision : Int32) -> (Binary, Binary)? {
  if work_precision >= binary_constants_split_min_precision {
    binary_pi_split_bounds(work_precision)
  } else {
    binary_pi_series_compute(work_precision)
  }
}
