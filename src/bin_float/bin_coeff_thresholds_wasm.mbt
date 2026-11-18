///|
let bin_coeff_toom3_threshold = 4096

///|
let bin_coeff_ntt_mul_threshold = 4096

///|
let bin_coeff_ntt_square_threshold = 3072

///|
let bin_coeff_square_recursive_threshold = 768

///|
let bin_coeff_sqrt_dc_base_bits = 512

///|
/// Working precision from which the bit-burst enclosure of `exp` replaces the
/// series (measured crossover on this target).
let binary_exp_burst_min_precision = 1088

///|
/// Limb count (64-bit limbs) below which the schoolbook product beats the
/// Karatsuba step of the word-range multiplication.
let bin_coeff_words_karatsuba_cutoff : Int32 = 32

///|
/// 32-bit limb count below which the schoolbook product beats the Karatsuba
/// step of the 32-bit-limb multiplication.
let bin_coeff_limb32_karatsuba_cutoff : Int32 = 96

///|
/// Smallest operand length, in 64-bit limbs, that is multiplied through
/// 32-bit limbs (measured crossover on this target).
let bin_coeff_limb32_min_words : Int32 = 160

///|
/// Whether Knuth's division runs on 64-bit digits (a 64-bit digit step costs
/// four `i64.mul` on Wasm, so Wasm keeps 32-bit digits).
let bin_coeff_knuth_words_enabled : Bool = true

///|
/// Divisor length, in 32-bit limbs, from which division uses Burnikel-Ziegler.
let bin_coeff_bz_division_threshold = 192

///|
/// Divisor length, in 32-bit limbs, up to which the Burnikel-Ziegler
/// recursion ends in Knuth's algorithm.
let bin_coeff_bz_leaf_limbs = 128

///|
/// Divisor length, in 32-bit limbs, from which division uses Newton's
/// reciprocal.
let bin_coeff_newton_division_threshold = 1073741824

///|
/// Working precision from which the verified Newton step replaces the series for
/// `ln` of a number in (1, 2] (measured crossover on this target).
let binary_ln_burst_min_precision = 1280
