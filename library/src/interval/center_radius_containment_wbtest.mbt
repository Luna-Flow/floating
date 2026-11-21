// `Interval::from_midpoint_radius` (and `try_from_midpoint_radius`) must return an interval that contains the center it
// was given. The error of rounding the center to the precision is taken as an
// upper bound; it was computed from an exact difference made at its own bit
// length in the nearest mode, so below the normal range a difference of a few
// bits underflowed to zero.

///|
fn ccr_next(state : Ref[UInt64]) -> UInt64 {
  let mut x = state.val
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  state.val = x
  x
}

///|
fn ccr_interval(
  center : @binary.Binary,
  radius : @binary.Binary,
  precision : Int32,
) -> Interval {
  Interval::from_midpoint_radius(center, radius, precision~)
}

///|
test "the interval of a center near the bottom of the range contains the center" {
  // center = 4296885932855670455593739022497658821269217831 * 2^-1073741878
  // (152 bits, stored at 200), radius = 34625 * 2^-1073741882, interval of 128 bits.
  // Rounding the center to 128 bits lands in the subnormal range: the rounding
  // error is 118,052,431 * 2^-1073741882 and was taken as 0, so the interval
  // [rounded center - radius, rounded center + radius] was
  // [68750174925690727289499824359962541140425537727,
  //  68750174925690727289499824359962541140425606977] * 2^-1073741882, while the
  // center is 68750174925690727289499824359962541140307485296 * 2^-1073741882.
  let center = @binary.Binary::make(
    @binary.BinCoeff::from_bytes_be(
      Bytes::from_array([
        0xc0, 0xad, 0xd4, 0xd9, 0xba, 0x4d, 0x3f, 0x29, 0x93, 0x2e, 0xe8, 0x0f, 0xef,
        0xf6, 0x9d, 0x80, 0x8f, 0x62, 0x27,
      ])[:],
    ),
    -1073741878,
    200,
  )
  let radius = @binary.Binary::make(
    @binary.BinCoeff::from_uint64(34625UL),
    -1073741882,
    200,
  )
  inspect(
    center.to_string(),
    content="4296885932855670455593739022497658821269217831p-1073741878",
  )
  let interval = ccr_interval(center, radius, 128)
  assert_true(interval.is_member(center))
  assert_true(interval.lower_bound().compare(center) <= 0)
  assert_true(center.compare(interval.upper_bound()) <= 0)
}

///|
/// The class: centers of 129 to 200 bits within 60 binades of the smallest
/// stored magnitude, radii of one to eleven bytes within 60 binades of it,
/// intervals of 24 to 128 bits (a seeded generator, 4,000 cases).
test "intervals built near the bottom of the range contain their centers" {
  let state = Ref(0x5851f42d4c957f2dUL)
  let e_min = @binary.binary_implementation_e_min
  let precisions = [24, 53, 64, 113, 128]
  let mut escaped = 0
  for _ in 0..<4000 {
    let center_bytes : Array[Byte] = []
    let n = 17 + (ccr_next(state) % 8UL).to_int()
    for _ in 0..<n {
      center_bytes.push((ccr_next(state) % 256UL).to_int().to_byte())
    }
    center_bytes[n - 1] = center_bytes[n - 1] | b'\x01'
    let radius_bytes : Array[Byte] = []
    let m = 1 + (ccr_next(state) % 11UL).to_int()
    for _ in 0..<m {
      radius_bytes.push((ccr_next(state) % 256UL).to_int().to_byte())
    }
    radius_bytes[m - 1] = radius_bytes[m - 1] | b'\x01'
    let center = @binary.Binary::make(
      @binary.BinCoeff::from_bytes_be(Bytes::from_array(center_bytes)[:]),
      e_min - 60 + (ccr_next(state) % 120UL).to_int(),
      200,
      negative=ccr_next(state) % 2UL == 0UL,
    )
    let radius = @binary.Binary::make(
      @binary.BinCoeff::from_bytes_be(Bytes::from_array(radius_bytes)[:]),
      e_min - 60 + (ccr_next(state) % 120UL).to_int(),
      200,
    )
    let precision = precisions[(ccr_next(state) % 5UL).to_int()]
    let interval = ccr_interval(center, radius, precision)
    if !interval.is_member(center) {
      escaped += 1
    }
  }
  assert_eq(escaped, 0)
}
