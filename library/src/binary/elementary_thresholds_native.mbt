///|
/// Working precision from which the bit-burst enclosure of `exp` replaces the
/// series (measured crossover on this target).
let binary_exp_burst_min_precision = 1024

///|
/// Working precision up to which the table-based `exp` kernel is the first choice
/// (measured crossover against the bit-burst and series paths on this target).
let binary_exp_table_max_precision = 1792

///|
/// Working precision from which the verified Newton step replaces the series for
/// `ln` of a number in (1, 2] (measured crossover on this target).
let binary_ln_burst_min_precision = 1152

///|
/// Working precision from which the bit-burst enclosure of `sin` and `cos`
/// replaces the reduction and the series (measured crossover on this target).
let binary_trig_burst_min_precision = 1536

///|
/// Working precision from which the outermost `ln` call starts with a Newton
/// step on the table kernel (measured crossover on this target; the nested
/// steps keep `binary_ln_burst_min_precision`). Re-measured after the fixed-point
/// series moved to limb arrays: the series is cheaper than the step below 768 and
/// equal to it there, on the assembly rows and on the C rows alike.
let binary_ln_entry_min_precision = 768

///|
/// Working precision from which the outermost `ln` call uses the arithmetic-geometric
/// mean (measured crossover on this target, re-measured after the series moved to
/// limb arrays: the Newton step is cheaper up to 1088 working bits on the assembly
/// and the C rows, the mean from 1152).
let binary_ln_agm_min_precision : Int32 = 1152

///|
/// Chunk constants of the bit-burst kernels (`exp`, `sin`, `cos`) as functions of
/// the working precision, measured on Native by instruction counts at 1024, 2048,
/// 4096 and 8192 bits of precision (working precision + 64) on three arguments
/// per size (a random value in [1, 2), one near 2^-9, one near the top of the
/// reduced range). The constants of `elementary_burst_exp.mbt` (16, 4, 40) are the
/// best at 8192 bits; below `binary_burst_small_work_max` a larger first chunk,
/// factor 8 and 80 terms before the splitting win, between the two bounds the same
/// with factor 4. No cell of the table is more than 1.01 of the old setting.
let binary_burst_small_work_max : Int32 = 3000

///|
let binary_burst_mid_work_max : Int32 = 6000

///|
fn binary_burst_first_chunk(work : Int32) -> Int32 {
  if work <= binary_burst_mid_work_max {
    24
  } else {
    binary_exp_burst_first_chunk
  }
}

///|
fn binary_burst_chunk_factor(work : Int32) -> Int32 {
  if work <= binary_burst_small_work_max {
    8
  } else {
    binary_exp_burst_chunk_factor
  }
}

///|
fn binary_burst_split_min_terms(work : Int32) -> Int32 {
  if work <= binary_burst_mid_work_max {
    80
  } else {
    binary_exp_burst_split_min_terms
  }
}

///|
/// Chunk constants of the `exp` bit-burst kernel alone, as functions of the working
/// precision `w`, from a sweep of 24 settings at precisions 1024 to 6144 bits on
/// five arguments per size (three random values in [1, 2), one near 2^-9, one near
/// the top of the reduced range), by instruction counts of one executable with
/// explicit settings, in both native states (the default assembly rows and
/// `LUNA_FLOATING_LIMBS=c`): no argument above 1.00 of (16, 4, 40) in the default
/// state and none above 1.01 in the C state at any measured size. `w <= 2200`:
/// (24, 8, 80); `2200 < w <= 2700`: (24, 8, 120); `2700 < w <= 6000`: (24, 4, 80);
/// above: (16, 4, 40). `sin` and `cos` keep the functions above.
let binary_exp_small_work_max : Int32 = 2200

///|
let binary_exp_gap_work_max : Int32 = 2700

///|
fn binary_exp_first_chunk_for(work : Int32) -> Int32 {
  if work <= binary_burst_mid_work_max {
    24
  } else {
    binary_exp_burst_first_chunk
  }
}

///|
fn binary_exp_chunk_factor_for(work : Int32) -> Int32 {
  if work <= binary_exp_gap_work_max {
    8
  } else if work <= binary_burst_mid_work_max {
    4
  } else {
    binary_exp_burst_chunk_factor
  }
}

///|
fn binary_exp_split_min_terms_for(work : Int32) -> Int32 {
  if work <= binary_exp_small_work_max {
    80
  } else if work <= binary_exp_gap_work_max {
    120
  } else if work <= binary_burst_mid_work_max {
    80
  } else {
    binary_exp_burst_split_min_terms
  }
}
