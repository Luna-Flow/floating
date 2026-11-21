///|
// oracle: A
// source: ref_pi_interval, bounds of pi written by tools/interval_pi_oracle.py (Python integers, Machin's formula)
// shares: nothing (ref_pi_interval uses only Binary::from_hex and with_precision)
test "certified_pi_interval is [RD(pi), RU(pi)] at the precision" {
  for p in [2, 24, 53, 64, 113, 177, 200, 400, 464, 1000, 2048] {
    let got = certified_pi_interval(p)
    let want = ref_pi_interval(p)
    assert_true(got.lo_.compare(want.lo_) == 0)
    assert_true(got.hi_.compare(want.hi_) == 0)
  }
}
