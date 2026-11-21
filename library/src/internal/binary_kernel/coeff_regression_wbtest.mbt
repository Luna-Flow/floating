///|
/// Regression digests of `Coeff` arithmetic (issue #19).
///
/// Oracle: level A. The 12 digests below are reproduced from the definition of
/// each operation by `tools/kernel_oracle.py` (table `regression`: CPython
/// integers, no library of this repository), which regenerates the operands
/// from the same seed with the same generator and shapes as this file.
/// `python3 tools/kernel_oracle.py --check` fails when a digest here differs;
/// `tools/kernel_oracle_test.py` runs it in the quick gate. The digests were
/// first recorded with the 32-bit-limb implementation, the one before the
/// 64-bit-limb work; since the generator reproduces them they do not rest on
/// any implementation in this repository.
///
/// A `Coeff` result is a unique integer, so every implementation (64-bit
/// limbs, new thresholds, new kernels) must reproduce them exactly. The corpus
/// uses random and adversarial values: all ones, single bits, `2^k` and
/// `2^k +- 1`, zero limbs inside a value, one operand much longer than the
/// other. Only the public `Coeff` API is used, so the same digests also hold
/// for the JavaScript `bigint` backend.
///
/// Reach: the largest operand has 131,073 bits (2,049 limbs of 64 bits). This
/// file therefore crosses the thresholds that lie below that size (schoolbook,
/// Karatsuba, Knuth, Burnikel-Ziegler, the integer square root up to 2,049
/// limbs, radix text up to 3,100 bits) and does not reach what lies above it
/// on native: the NTT and Toom-3 products from 4,096 limbs, the NTT square,
/// the divide-and-conquer radix parse, the short product and the word
/// recursion of the square root above 33,000 bits. Those need other tables.
struct RegressionRandom {
  mut regression_state : UInt64
}

///|
fn RegressionRandom::next(self : RegressionRandom) -> UInt64 {
  self.regression_state = self.regression_state * 6364136223846793005UL +
    1442695040888963407UL
  self.regression_state >> 11
}

///|
/// A value of exactly `bits` bits (`bits >= 1`) in one of several shapes.
fn regression_value(
  random : RegressionRandom,
  bits : Int32,
  shape : Int32,
) -> Coeff {
  let length = (bits + 7) / 8
  let bytes = FixedArray::make(length, 0)
  let top_mask = (1 << ((bits - 1) % 8 + 1)) - 1
  match shape {
    0 =>
      // random with the top bit set
      for index in 0..<length {
        bytes[index] = (random.next() & 0xffUL).to_int()
      }
    1 =>
      // all ones
      for index in 0..<length {
        bytes[index] = 0xff
      }
    2 => () // 2^(bits - 1), set below
    3 => bytes[length - 1] = 1 // 2^(bits - 1) + 1
    4 =>
      // 2^(bits - 1) - 1 style: all ones below the top bit
      for index in 0..<length {
        bytes[index] = 0xff
      }
    5 =>
      // sparse: a few random set bits
      for _ in 0..<5 {
        let position = (random.next() % bits.to_uint64()).to_int()
        let byte = length - 1 - position / 8
        bytes[byte] = bytes[byte] | (1 << (position % 8))
      }
    _ =>
      // zero limbs inside: random head and tail words, zeros between
      for index in 0..<length {
        let near_end = index < 8 || index >= length - 8
        bytes[index] = if near_end {
          (random.next() & 0xffUL).to_int()
        } else {
          0
        }
      }
  }
  bytes[0] = bytes[0] & top_mask
  if shape == 4 {
    bytes[0] = bytes[0] & (top_mask >> 1)
    if bits == 1 {
      bytes[0] = 1
    }
  }
  // force the top bit so the value has exactly `bits` bits (shape 4 has bits - 1)
  if shape != 4 {
    bytes[0] = bytes[0] | (1 << ((bits - 1) % 8))
  }
  let source = Bytes::makei(length, i => bytes[i].to_byte())
  Coeff::from_bytes_be(source[:])
}

///|
fn regression_mix(state : UInt64, value : Coeff) -> UInt64 {
  let mut hash = state
  for byte in value.to_bytes_be() {
    hash = (hash ^ byte.to_uint64()) * 0x100000001b3UL
  }
  // separate consecutive values
  (hash ^ 0xffUL) * 0x100000001b3UL
}

///|
fn regression_mix_int(state : UInt64, value : Int32) -> UInt64 {
  (state ^ (value.to_uint64() & 0xffffffffUL)) * 0x100000001b3UL
}

///|
fn regression_mix_string(state : UInt64, text : String) -> UInt64 {
  let mut hash = state
  for char in text {
    hash = (hash ^ char.to_int().to_uint64()) * 0x100000001b3UL
  }
  hash * 0x100000001b3UL
}

///|
let regression_sizes : Array[Int32] = [
  1, 2, 31, 32, 33, 63, 64, 65, 100, 127, 128, 129, 130, 160, 191, 192, 193, 255,
  256, 257, 320, 512, 1000, 1023, 1024, 1025, 2047, 2048, 2049, 3071, 3072, 3073,
  3100, 4096, 6143, 6144, 6145, 8192,
]

///|
let regression_large_sizes : Array[Int32] = [
  16383, 16384, 16385, 24575, 24576, 24577, 65535, 65536, 65537, 131071, 131072,
  131073,
]

///|
struct RegressionDigests {
  add : UInt64
  sub : UInt64
  compare : UInt64
  shift : UInt64
  bits : UInt64
  mul : UInt64
  square : UInt64
  div : UInt64
  gcd : UInt64
  sqrt : UInt64
  text : UInt64
  large_mul : UInt64
}

///|
fn regression_digests() -> RegressionDigests {
  let random = { regression_state: 0xC0FFEE1234567UL, }
  let basis = 0xcbf29ce484222325UL
  let mut add = basis
  let mut sub = basis
  let mut compare = basis
  let mut shift = basis
  let mut bits = basis
  let mut mul = basis
  let mut square = basis
  let mut div = basis
  let mut gcd = basis
  let mut sqrt = basis
  let mut text = basis
  let mut large_mul = basis
  for size in regression_sizes {
    for shape in 0..<7 {
      let a = regression_value(random, size, shape)
      let b = regression_value(random, size, (shape + 3) % 7)
      let c = regression_value(random, Int32::max(1, size / 3 + 1), shape)
      let small = regression_value(random, 30, 0)
      let word = regression_value(random, 64, 0)
      // addition, subtraction, comparison, bit queries
      add = regression_mix(add, a.add(b))
      add = regression_mix(add, a.add(c))
      add = regression_mix(add, a.add(a))
      let (larger, smaller) = if a.compare(b) >= 0 { (a, b) } else { (b, a) }
      sub = regression_mix(sub, larger.sub_checked(smaller).unwrap())
      sub = regression_mix(sub, larger.sub_checked(larger).unwrap())
      compare = regression_mix_int(compare, a.compare(b))
      compare = regression_mix_int(compare, a.compare(c))
      compare = regression_mix_int(compare, c.compare(a))
      compare = regression_mix_int(compare, a.compare(a))
      bits = regression_mix_int(bits, a.bit_length())
      bits = regression_mix_int(bits, a.ctz())
      bits = regression_mix_int(bits, if a.test_bit(size / 2) { 1 } else { 0 })
      bits = regression_mix_int(bits, if a.test_bit(size - 1) { 1 } else { 0 })
      bits = regression_mix_int(bits, if a.test_bit(size) { 1 } else { 0 })
      // shifts and bit operations
      for amount in [1, 31, 32, 33, 63, 64, 65, size / 2, size + 7] {
        shift = regression_mix(shift, a.shift_left(amount))
        shift = regression_mix(shift, a.shift_right(amount))
      }
      shift = regression_mix(shift, a.bit_and(b))
      shift = regression_mix(shift, a.bit_or(c))
      shift = regression_mix(shift, a.bit_xor(b))
      // multiplication and squaring
      mul = regression_mix(mul, a.mul(b))
      mul = regression_mix(mul, a.mul(c))
      mul = regression_mix(mul, c.mul(a))
      mul = regression_mix(mul, a.mul(small))
      mul = regression_mix(mul, a.mul(word))
      square = regression_mix(square, a.square())
      square = regression_mix(square, c.square())
      // division
      if size <= 8192 {
        let (quotient, remainder) = a.div_rem_checked(small).unwrap()
        div = regression_mix(regression_mix(div, quotient), remainder)
        let (quotient, remainder) = a.div_rem_checked(word).unwrap()
        div = regression_mix(regression_mix(div, quotient), remainder)
        let (quotient, remainder) = a.div_rem_checked(c).unwrap()
        div = regression_mix(regression_mix(div, quotient), remainder)
        let wide = a.mul(b)
        let (quotient, remainder) = wide.div_rem_checked(a).unwrap()
        div = regression_mix(regression_mix(div, quotient), remainder)
        let (quotient, remainder) = wide.add(c).div_rem_checked(b).unwrap()
        div = regression_mix(regression_mix(div, quotient), remainder)
      }
      // gcd, square root, text
      if size <= 1025 {
        gcd = regression_mix(gcd, a.gcd(b))
        gcd = regression_mix(gcd, a.mul(c).gcd(a.mul(small)))
      }
      if size <= 2049 {
        let (root, remainder) = bin_coeff_sqrt_rem_kernel(a)
        sqrt = regression_mix(regression_mix(sqrt, root), remainder)
        let (root, remainder) = bin_coeff_sqrt_rem_kernel(a.square().add(c))
        sqrt = regression_mix(regression_mix(sqrt, root), remainder)
      }
      if size <= 3100 {
        text = regression_mix_string(text, a.to_radix_string(10))
        text = regression_mix_string(text, a.to_radix_string(16))
        text = regression_mix_string(text, c.to_radix_string(7))
        text = regression_mix(
          text,
          Coeff::parse(a.to_radix_string(10)).unwrap(),
        )
      }
    }
  }
  for size in regression_large_sizes {
    for shape in [0, 1, 6] {
      let a = regression_value(random, size, shape)
      let b = regression_value(random, size - 1, (shape + 1) % 7)
      large_mul = regression_mix(large_mul, a.mul(b))
      large_mul = regression_mix(large_mul, a.square())
      large_mul = regression_mix(large_mul, a.add(b))
      large_mul = regression_mix(
        large_mul,
        a.mul(regression_value(random, 200, 0)),
      )
    }
  }
  {
    add,
    sub,
    compare,
    shift,
    bits,
    mul,
    square,
    div,
    gcd,
    sqrt,
    text,
    large_mul,
  }
}

///|
test "Coeff regression digests (recorded with the 32-bit-limb implementation)" {
  let d = regression_digests()
  assert_eq(d.add, 16834754901792827537UL)
  assert_eq(d.sub, 12975145108348538842UL)
  assert_eq(d.compare, 3980940454005479485UL)
  assert_eq(d.shift, 157656410054604387UL)
  assert_eq(d.bits, 9530205330146749551UL)
  assert_eq(d.mul, 136722308119388799UL)
  assert_eq(d.square, 16009303912518823917UL)
  assert_eq(d.div, 8569676811794716520UL)
  assert_eq(d.gcd, 6359571565459609538UL)
  assert_eq(d.sqrt, 14086888363061168723UL)
  assert_eq(d.text, 9055928250472136776UL)
  assert_eq(d.large_mul, 8487456071819769317UL)
}
