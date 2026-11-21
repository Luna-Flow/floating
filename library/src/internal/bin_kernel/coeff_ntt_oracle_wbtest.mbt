///|
/// Oracle of the number-theoretic transform of `Coeff` (`coeff_ntt_nonjs.mbt`):
/// level A. Every expected value is computed by `tools/kernel_oracle.py` with
/// CPython integers from the definitions, and the table rows are in
/// `coeff_ntt_oracle_rows_wbtest.mbt` (header: the meaning of each kind).
///
/// - the constants (`prime1`, `root1`, `nprime1`, `r_prime1`, `r2_prime1`, the same for
///   the second prime, `crt_inverse`, `max_length`) are compared with literals the
///   generator derives: `p = 119 2^23 + 1` and `45 2^24 + 1`, the roots 3 and 11 are
///   checked primitive there (no `(p - 1) / q` power is 1 for a prime factor `q`),
///   `nprime = -p^-1 mod 2^32`, `r = 2^32 mod p`, `r2 = r^2 mod p`;
///   `crt_inverse = p1^-1 mod p2`, `max_length` the largest power of two dividing both `p - 1`;
/// - Montgomery multiplication and power (`mont`): the products and powers of edge and
///   pseudo-random residues equal `x y mod p` and `pow(x, e, p)`;
/// - the digit fill (`fill`, the 64-bit-limb route `bin_coeff_ntt_fill_words`, which is
///   `bin_coeff_ntt_fill` on native; the 32-bit view is Wasm only and is not run here), the
///   transform-multiply-inverse convolution (`conv`: `bin_coeff_ntt_convolution_mod`, one
///   prime, the digits of two operands of up to 1,000 limbs against the naive convolution of
///   the digit lists modulo the prime), the Chinese remainder step (`crt`) and the
///   reassembly with carries (`recon`: `bin_coeff_ntt_reconstruct_words`).
///
/// The product of the whole pipeline at production sizes is checked by the product table
/// (`coeff_product_oracle_wbtest.mbt`). The convolution rows run in every state of the limb
/// tier; the transform itself uses no row primitive, so the three states differ only in
/// what the conversion shares with them.

///|
fn ntt_oracle_constant(name : String) -> UInt64 {
  match name {
    "prime1" => bin_coeff_ntt_prime1
    "prime2" => bin_coeff_ntt_prime2
    "root1" => bin_coeff_ntt_root1
    "root2" => bin_coeff_ntt_root2
    "nprime1" => bin_coeff_ntt_nprime1
    "nprime2" => bin_coeff_ntt_nprime2
    "r_prime1" => bin_coeff_ntt_r_prime1
    "r_prime2" => bin_coeff_ntt_r_prime2
    "r2_prime1" => bin_coeff_ntt_r2_prime1
    "r2_prime2" => bin_coeff_ntt_r2_prime2
    "crt_inverse" => bin_coeff_ntt_crt_inverse
    "max_length" => bin_coeff_ntt_max_length.to_uint64()
    _ => abort("unknown NTT constant \{name}")
  }
}

///|
/// The prime, primitive root, `nprime`, `r2` and `r` of prime 1 or 2.
fn ntt_oracle_prime(index : Int32) -> (UInt64, UInt64, UInt64, UInt64, UInt64) {
  if index == 1 {
    (
      bin_coeff_ntt_prime1, bin_coeff_ntt_root1, bin_coeff_ntt_nprime1, bin_coeff_ntt_r2_prime1,
      bin_coeff_ntt_r_prime1,
    )
  } else {
    (
      bin_coeff_ntt_prime2, bin_coeff_ntt_root2, bin_coeff_ntt_nprime2, bin_coeff_ntt_r2_prime2,
      bin_coeff_ntt_r_prime2,
    )
  }
}

///|
/// `count` pairs: the edges, then pairs drawn modulo the two limits.
fn ntt_oracle_pairs(
  count : Int32,
  random : RegressionRandom,
  limit0 : UInt64,
  limit1 : UInt64,
  edges : Array[(UInt64, UInt64)],
) -> Array[(UInt64, UInt64)] {
  let pairs : Array[(UInt64, UInt64)] = []
  for edge in edges {
    pairs.push(edge)
  }
  while pairs.length() < count {
    let first = random.next() % limit0
    let second = random.next() % limit1
    pairs.push((first, second))
  }
  pairs
}

///|
fn ntt_oracle_fold(state : UInt64, word : UInt32) -> UInt64 {
  regression_mix_int(state, word.reinterpret_as_int())
}

///|
fn ntt_oracle_run(row : Array[String]) -> Unit raise {
  let name = row[0]
  let kind = row[1]
  let seed = oracle_u64(row[7])
  let expected = oracle_u64(row[8])
  let random : RegressionRandom = { regression_state: seed, }
  let basis = 0xcbf29ce484222325UL
  match kind {
    "const" =>
      if ntt_oracle_constant(row[2]) != expected {
        fail(
          "\{name}: the constant differs from the definition computed by CPython",
        )
      }
    "mont" => {
      let (p, _, np, r2, r) = ntt_oracle_prime(oracle_int(row[3]))
      let edges = [
        (0UL, 0UL),
        (1UL, 1UL),
        (p - 1UL, p - 1UL),
        (p - 2UL, 3UL),
        ((1UL << 31) % p, p - 1UL),
        (p - 1UL, 1UL),
      ]
      let mut state = basis
      for pair in ntt_oracle_pairs(oracle_int(row[2]), random, p, p, edges) {
        let (x, y) = pair
        let product = bin_coeff_ntt_from_montgomery(
          bin_coeff_ntt_montgomery_mul(
            bin_coeff_ntt_to_montgomery(x, p, np, r2),
            bin_coeff_ntt_to_montgomery(y, p, np, r2),
            p,
            np,
          ),
          p,
          np,
        )
        let exponent = (x * 0x9E3779B1UL + y) % 4294967296UL
        let power = bin_coeff_ntt_pow_normal(x, exponent, p, np, r2, r)
        state = ntt_oracle_fold(state, product.to_uint())
        state = ntt_oracle_fold(state, power.to_uint())
      }
      if state != expected {
        fail("\{name}: Montgomery product or power differs from CPython")
      }
    }
    "crt" => {
      let p1 = bin_coeff_ntt_prime1
      let p2 = bin_coeff_ntt_prime2
      let edges = [
        (0UL, 0UL),
        (p1 - 1UL, p2 - 1UL),
        (p2 - 1UL, 0UL),
        (0UL, p2 - 1UL),
        (p2, 0UL),
        (p2 + 5UL, 7UL),
        (1UL, 0UL),
        (p1 - 1UL, 0UL),
      ]
      let mut state = basis
      for pair in ntt_oracle_pairs(oracle_int(row[2]), random, p1, p2, edges) {
        let (r1, r2) = pair
        state = regression_mix(
          state,
          Coeff::from_uint64(bin_coeff_ntt_crt(r1, r2)),
        )
      }
      if state != expected {
        fail("\{name}: the Chinese remainder step differs from CPython")
      }
    }
    "recon" => {
      let p1 = bin_coeff_ntt_prime1
      let p2 = bin_coeff_ntt_prime2
      let count = oracle_int(row[2])
      let coefficients : Array[UInt64] = [
        0UL,
        1UL,
        0xffffUL,
        1UL << 16,
        (1UL << 50) - 1UL,
        p1 * p2 - 1UL,
        p1,
        p2,
        p1 + 1UL,
      ]
      while coefficients.length() < count {
        coefficients.push(random.next() % (1UL << 50))
      }
      let residues1 = FixedArray::make(count, 0U)
      let residues2 = FixedArray::make(count, 0U)
      for index in 0..<count {
        residues1[index] = (coefficients[index] % p1).to_uint()
        residues2[index] = (coefficients[index] % p2).to_uint()
      }
      let value = bin_coeff_ntt_reconstruct_words(
        residues1,
        residues2,
        count,
        (16 * count + 66 + 63) / 64,
      )
      if regression_mix(basis, value) != expected {
        fail("\{name}: the reassembly differs from CPython")
      }
    }
    "fill" => {
      let (p, _, np, r2, _) = ntt_oracle_prime(oracle_int(row[2]))
      let value = regression_value(
        random,
        oracle_int(row[3]),
        oracle_int(row[4]),
      )
      let digits = bin_coeff_ntt_digit_length(value)
      for variant in 0..<2 {
        let destination = FixedArray::make(digits + 4, 0U)
        if variant == 0 {
          bin_coeff_ntt_fill(destination, value, digits, p, np, r2)
        } else {
          bin_coeff_ntt_fill_words(destination, value, digits, p, np, r2)
        }
        let mut state = basis
        for index in 0..<digits {
          state = ntt_oracle_fold(state, destination[index])
        }
        if state != expected {
          fail("\{name}: the digits differ from CPython (variant \{variant})")
        }
      }
    }
    _ => {
      let (p, g, np, r2, r) = ntt_oracle_prime(oracle_int(row[2]))
      let shapes = oracle_int(row[5])
      let square = row[6] == "1"
      let left = regression_value(random, oracle_int(row[3]), shapes / 10)
      let right = if square {
        left
      } else {
        regression_value(random, oracle_int(row[4]), shapes % 10)
      }
      let count = bin_coeff_ntt_digit_length(left) +
        bin_coeff_ntt_digit_length(right) -
        1
      let length = bin_coeff_ntt_transform_length(count)
      let result = bin_coeff_ntt_convolution_mod(
        left, right, square, length, count, p, g, np, r2, r,
      )
      let mut state = basis
      for index in 0..<count {
        state = ntt_oracle_fold(state, result[index])
      }
      if state != expected {
        fail("\{name}: the convolution differs from CPython")
      }
    }
  }
}

///|
fn ntt_oracle_run_rows(is_gate : Bool) -> Int32 raise {
  let mut total = 0
  for row in oracle_rows(ntt_oracle_table) {
    let big = row[1] == "conv" &&
      (oracle_int(row[3]) > 64 * 129 || oracle_int(row[4]) > 64 * 129)
    if big == is_gate {
      total += 1
      ntt_oracle_run(row)
    }
  }
  total
}

///|
// oracle: A
// source: constants, Montgomery products and powers, digit fills, convolutions, Chinese remainder values and reassembled integers computed by tools/kernel_oracle.py with CPython integers (pow, naive convolution, int arithmetic)
// shares: the construction of the operands (regression_value, which has the level A digests of coeff_regression_wbtest.mbt) and the NTT's own Montgomery helpers in the convolution rows, which the mont, fill and constant rows check against CPython
test "oracle: number-theoretic transform against CPython, operands up to 129 limbs" {
  assert_true(ntt_oracle_run_rows(false) > 150)
}

///|
// oracle: A
// source: convolutions of the digit lists computed by tools/kernel_oracle.py with CPython integers (naive convolution)
// shares: the construction of the operands (regression_value) and the NTT's own Montgomery helpers, checked by the mont rows
#skip("binary gate stage: convolutions of up to 1,000 limbs (4,000 digits)")
test "oracle: number-theoretic transform against CPython, convolutions of 130 to 1,000 limbs" {
  assert_true(ntt_oracle_run_rows(true) > 0)
}
