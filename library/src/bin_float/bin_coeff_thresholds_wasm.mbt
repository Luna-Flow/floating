///|
/// Shorter-operand length, in 64-bit limbs, from which a balanced product uses
/// Toom-3 instead of the word Karatsuba (it equals the NTT cutoff, so it is only
/// reached where the NTT transform length does not fit).
let bin_coeff_toom3_min_words = 2048

///|
/// Shorter-operand length, in 64-bit limbs, from which a product uses the
/// two-prime NTT.
let bin_coeff_ntt_mul_min_words = 2048

///|
/// Operand length, in 64-bit limbs, from which a square uses the two-prime NTT.
let bin_coeff_ntt_square_min_words = 1536

///|
/// Operand length, in 64-bit limbs, from which a square that is not an NTT or
/// Karatsuba square runs Toom-3 instead of the general product.
let bin_coeff_square_toom3_min_words = 384

///|
/// Operand length, in 64-bit limbs, below which a square that does not take the
/// word Karatsuba square runs the schoolbook square, and above which it runs the
/// general product.
let bin_coeff_square_recursive_min_words = 384

///|
/// Working precision from which the bit-burst enclosure of `exp` replaces the
/// series (measured crossover on this target).
let binary_exp_burst_min_precision = 1088

///|
/// Working precision up to which the table-based `exp` kernel is the first choice
/// (measured crossover against the bit-burst and series paths on this target).
let binary_exp_table_max_precision = 2048

///|
/// Limb count (64-bit limbs) below which the schoolbook product beats the
/// Karatsuba step of the word-range multiplication.
let bin_coeff_words_karatsuba_cutoff : Int32 = 32

///|
/// 32-bit limb count below which the schoolbook product beats the Karatsuba
/// step of the 32-bit-limb multiplication (the Wasm route).
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
/// Divisor length, in 64-bit limbs, from which division uses Burnikel-Ziegler.
let bin_coeff_bz_division_min_words = 96

///|
/// Divisor length, in 64-bit limbs, up to which the Burnikel-Ziegler
/// recursion ends in Knuth's algorithm.
let bin_coeff_bz_leaf_words = 64

///|
/// Divisor length, in 64-bit limbs, from which division uses Newton's
/// reciprocal (never selected: the routine stays for tests).
let bin_coeff_newton_division_min_words = 536870912

///|
/// Working precision from which the verified Newton step replaces the series for
/// `ln` of a number in (1, 2] (measured crossover on this target).
let binary_ln_burst_min_precision = 1280

///|
/// Working precision from which the bit-burst enclosure of `sin` and `cos`
/// replaces the reduction and the series (measured crossover on this target).
let binary_trig_burst_min_precision = 2112

///|
/// Whether the integer square roots of up to 256 bits use the word kernels
/// (`bin_coeff_sqrt_words_nonjs.mbt`) instead of the restoring loops.
let bin_coeff_sqrt_words_enabled = false

///|
/// Limb count (64-bit limbs) below which the half-product schoolbook square
/// beats the Karatsuba square step of the word-range squaring.
let bin_coeff_words_square_cutoff : Int32 = 32

///|
/// Whether squaring runs the word-range Karatsuba square
/// (`bin_coeff_words_sqr_scratch`) between the schoolbook square and the NTT.
let bin_coeff_square_words_enabled = false

///|
/// Number of 64-bit limbs from which `BinCoeff::to_radix_string` formats by
/// divide and conquer instead of dividing a copy of the limbs chunk by chunk.
let bin_coeff_radix_format_dc_words = 64

///|
/// Number of digit chunks from which `BinCoeff::parse` combines chunks by
/// divide and conquer instead of accumulating them in place.
let bin_coeff_radix_parse_dc_chunks = 4608
