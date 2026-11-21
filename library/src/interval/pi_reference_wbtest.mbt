///|
// oracle-file: A
// producer: tools/interval_pi_oracle.py
// input: pi by Machin's formula in Python integers, 2048 fractional bits, outward margin
// library-ran: no
// shares: Binary::from_hex (reads the literal, exact at 2200 bits) and Binary::with_precision (directed rounding to p bits); ref_pi_interval(p) is [RD(pi), RU(pi)] at p bits (p <= 2048), which the generator proves for every p from 2 to 2048
//   from_hex is right on these inputs by the hexadecimal reader tests of the binary package (hex.mbt and its tables), with_precision by the rounding tests of binary and by certified_pi_wbtest.mbt, which compares the result with the Python bounds for 11 precisions
// check: python3 tools/interval_pi_oracle.py --check

///|
let ref_pi_lo_hex : String = "0x3243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89452821e638d01377be5466cf34e90c6cc0ac29b7c97c50dd3f84d5b5b54709179216d5d98979fb1bd1310ba698dfb5ac2ffd72dbd01adfb7b8e1afed6a267e96ba7c9045f12c7f9924a19947b3916cf70801f2e2858efc16636920d871574e69a458fea3f4933d7e0d95748f728eb658718bcd5882154aee7b54a41dc25a59b59c30d5392af26013c5d1b023286085f0ca417918b8db38ef8e79dcb0603a180e6c9e0e8bb01e8a3ed71577c1bd314b2778af2fda55605c60e65525f3aa55ab945748986263e8144055ca396a2aab10b6b4cc5c341141e8cea15486af7c72e993p-2048"

///|
let ref_pi_hi_hex : String = "0x3243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89452821e638d01377be5466cf34e90c6cc0ac29b7c97c50dd3f84d5b5b54709179216d5d98979fb1bd1310ba698dfb5ac2ffd72dbd01adfb7b8e1afed6a267e96ba7c9045f12c7f9924a19947b3916cf70801f2e2858efc16636920d871574e69a458fea3f4933d7e0d95748f728eb658718bcd5882154aee7b54a41dc25a59b59c30d5392af26013c5d1b023286085f0ca417918b8db38ef8e79dcb0603a180e6c9e0e8bb01e8a3ed71577c1bd314b2778af2fda55605c60e65525f3aa55ab945748986263e8144055ca396a2aab10b6b4cc5c341141e8cea15486af7c72e994p-2048"

///|
fn ref_pi_interval(precision : Int32) -> Interval {
  let lo = @binary.Binary::from_hex(ref_pi_lo_hex, 2200).unwrap()
  let hi = @binary.Binary::from_hex(ref_pi_hi_hex, 2200).unwrap()
  Interval::from_bounds(
    lo.with_precision(
      precision,
      @binary.BinaryRoundingMode::RoundTowardNegative,
    ),
    hi.with_precision(
      precision,
      @binary.BinaryRoundingMode::RoundTowardPositive,
    ),
    precision~,
  )
}
