///|
/// Oracle of the product routes of `Coeff`: level A. The expected value of a
/// row is computed by `tools/kernel_oracle.py` (CPython integers, `a * b` and
/// `a * a`, no library of this repository) and folded into the FNV-1a digest
/// of its big-endian bytes; for the overlap-add rows, which are too large for
/// CPython to multiply quickly, it is the residues of the product modulo
/// 2^64 - 1, 2^61 - 1, 2147483587 and 2147483629 (error classes in the header
/// of the generator). Operands are regenerated from the seed of the row with
/// `regression_value`. The routes run on a row are the ones it names:
/// `mul` and `square` (the default, `bin_coeff_mul_large_dispatch` and
/// `bin_coeff_square_large_dispatch` above the cutoffs), `ntt`, `toom3` and
/// `words` called directly on the same operands, `square_ntt`, `overlap`.
/// The table is `coeff_product_oracle_rows_wbtest.mbt` (rows marked `pr` run
/// in the default test, rows marked `gate` in the `#skip` test that the binary
/// gate runs in the three states of the row implementation).

///|
fn product_oracle_run(row : Array[String]) -> Unit raise {
  let name = row[0]
  let kind = row[1]
  let routes = row[2].split(",").map(fn(part) { part.to_owned() }).collect()
  let left_limbs = oracle_int(row[3])
  let right_limbs = oracle_int(row[4])
  let seed = oracle_u64(row[7])
  let form = row[9]
  let random : RegressionRandom = { regression_state: seed, }
  let left = oracle_value(random, left_limbs, oracle_int(row[5]))
  let check = fn(route : String, result : Coeff) -> Unit raise {
    if form == "exact" {
      let expected = oracle_u64(row[10])
      if oracle_digest(result) != expected {
        fail("\{name}: route \{route} differs from the oracle (digest)")
      }
    }
  }
  if kind == "square" {
    for route in routes {
      match route {
        "square" => check(route, left.square())
        "square_ntt" => check(route, bin_coeff_square_ntt(left))
        _ => fail("\{name}: unknown route \{route}")
      }
    }
    return
  }
  let right = oracle_value(random, right_limbs, oracle_int(row[6]))
  if kind == "overlap" {
    let residues = oracle_residues(bin_coeff_mul_ntt_overlap(left, right))
    for index in 0..<4 {
      if residues[index] != oracle_u64(row[10 + index]) {
        fail("\{name}: overlap-add differs from the oracle (residue \{index})")
      }
    }
    return
  }
  for route in routes {
    match route {
      "mul" => check(route, left.mul(right))
      "ntt" => check(route, bin_coeff_mul_ntt(left, right))
      "toom3" => check(route, bin_coeff_mul_toom3(left, right))
      "words" => check(route, bin_coeff_mul_words(left, right))
      _ => fail("\{name}: unknown route \{route}")
    }
  }
}

///|
fn product_oracle_rows_where(where_ : String) -> Array[Array[String]] {
  oracle_rows(product_oracle_table).filter(fn(row) { row[8] == where_ })
}

///|
test "oracle: product routes equal the oracle, rows up to 600 limbs" {
  let rows = product_oracle_rows_where("pr")
  for row in rows {
    product_oracle_run(row)
  }
  assert_true(rows.length() > 300)
}

///|
#skip("full list: the binary gate runs it with --include-skipped, in the three states")
test "oracle: product routes equal the oracle, the NTT, Toom-3, squares and blocks at production sizes" {
  let rows = product_oracle_rows_where("gate")
  for row in rows {
    if row[1] != "overlap" {
      product_oracle_run(row)
    }
  }
  assert_true(rows.length() > 100)
}

///|
#skip("overlap-add: product of about 2^21 limbs; run by the binary gate in the three states")
test "oracle: the overlap-add product equals the oracle (residues)" {
  for row in product_oracle_rows_where("gate") {
    if row[1] == "overlap" {
      product_oracle_run(row)
    }
  }
}
