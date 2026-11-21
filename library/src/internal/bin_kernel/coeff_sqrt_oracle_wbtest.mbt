///|
/// Oracle of the square root routes of `Coeff`: level A. The expected value of a
/// row is computed by `tools/kernel_oracle.py` (CPython integers: `math.isqrt`,
/// `<<`; no library of this repository) and folded into the FNV-1a digest of the
/// root and the remainder, or of the packed value of `bin_coeff_sqrt_scaled_rounded`.
/// The radicand of a row is a `regression_value` operand (`v`) or `s^2 + delta`
/// with `delta` in -1, 0, 1 (`sq`: exact squares, squares minus one and plus one),
/// and the test checks the digest of the radicand, computed by CPython, before it
/// calls the route (the square is formed with `Coeff::square`, whose result is
/// thereby verified on each row, so that a wrong square cannot hide a wrong root).
/// The shapes of `s` (random, all ones, `2^k + 1`, zero limbs inside) put the
/// recursion's quotient estimate at `X` (the capped case) and the remainders at 0
/// and `2 s`.
///
/// Routes, and how it is known that a row takes one: `bin_coeff_sqrt_rem_kernel`
/// takes a radicand of up to 64 bits (`Inline64`), up to 128 bits (`Inline128`), up to
/// 256 bits the fixed-width word kernels and above that the recursion
/// `bin_coeff_sqrt_rem_words_recursive` (`coeff_sqrt_nonjs.mbt:137`); the sizes are
/// the bit lengths of the radicand, one either side of each limit and of
/// `64 n` for the limb counts `n` of the recursion levels (4, 6, 8, 12, ... 1,024).
/// The recursion halves down to 4 limbs (`n <= 4`,
/// `coeff_sqrt_array_nonjs.mbt:48`), so a radicand of `64 n` bits reaches
/// about `log2 (n / 4)` levels; the rows with `scaled` and `rounded` use
/// `bin_coeff_sqrt_rem_scaled` and `bin_coeff_sqrt_scaled_rounded` with a
/// shift (0, 1, 2, 63, 64, 65, 130, 257 bits), so that the shifted radicand
/// crosses the 256-bit limit from below and the odd shifts exercise the
/// normalisation by an even number of bits. The recursion has no counter: that a
/// row reaches a given level is read from the sizes, not checked at run time;
/// the mutations of the pull request show which defects the rows catch.

///|
fn sqrt_oracle_radicand(row : Array[String]) -> Coeff raise {
  let random : RegressionRandom = { regression_state: oracle_u64(row[5]), }
  let base = div_oracle_operand(row[3], Coeff::zero(), random)
  if row[2] == "v" {
    return base
  }
  let square = base.square()
  let delta = oracle_signed(row[4])
  if delta < 0 {
    match square.sub_checked(Coeff::one()) {
      Ok(smaller) => smaller
      Err(_) => fail("\{row[0]}: a square below one")
    }
  } else if delta > 0 {
    square.add(Coeff::one())
  } else {
    square
  }
}

///|
fn sqrt_oracle_run(row : Array[String]) -> Unit raise {
  let name = row[0]
  let route = row[1]
  let radicand = sqrt_oracle_radicand(row)
  if regression_mix(0xcbf29ce484222325UL, radicand) != oracle_u64(row[9]) {
    fail("\{name}: the radicand differs from CPython")
  }
  let scale = oracle_int(row[7])
  let precision = oracle_int(row[8])
  let expected = oracle_u64(row[10])
  let actual = match route {
    "kernel" => {
      let (root, remainder) = bin_coeff_sqrt_rem_kernel(radicand)
      div_oracle_pair_digest(root, remainder)
    }
    "scaled" => {
      let (root, remainder) = bin_coeff_sqrt_rem_scaled(radicand, scale)
      div_oracle_pair_digest(root, remainder)
    }
    _ =>
      regression_mix(
        0xcbf29ce484222325UL,
        bin_coeff_sqrt_scaled_rounded(radicand, scale, precision),
      )
  }
  if actual != expected {
    fail("\{name}: the square root differs from CPython (route \{route})")
  }
}

///|
fn sqrt_oracle_run_where(where_ : String) -> Int32 raise {
  let mut total = 0
  for row in oracle_rows(sqrt_oracle_table) {
    if row[6] == where_ {
      total += 1
      sqrt_oracle_run(row)
    }
  }
  total
}

///|
// oracle: A
// source: roots, remainders and packed rounded roots computed by tools/kernel_oracle.py with math.isqrt; the radicands are verified against CPython digests first
// shares: nothing
test "oracle: square root routes against CPython, radicands up to 4,100 bits" {
  assert_true(sqrt_oracle_run_where("pr") > 1000)
}

///|
// oracle: A
// source: roots, remainders and packed rounded roots computed by tools/kernel_oracle.py with math.isqrt; the radicands are verified against CPython digests first
// shares: nothing
#skip("binary gate stage: radicands from 4,101 to 65,537 bits")
test "oracle: square root routes against CPython, radicands from 4,101 to 65,537 bits" {
  assert_true(sqrt_oracle_run_where("gate") > 100)
}
