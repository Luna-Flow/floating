///|
/// Shorter-operand length, in 64-bit limbs, from which a balanced product uses
/// Toom-3 instead of the word Karatsuba (it equals the NTT cutoff, so it is only
/// reached where the NTT transform length does not fit).
let bin_coeff_toom3_min_words = 4096

///|
/// Shorter-operand length, in 64-bit limbs, from which a product uses the
/// two-prime NTT.
let bin_coeff_ntt_mul_min_words = 4096

///|
/// Operand length, in 64-bit limbs, from which a square uses the two-prime NTT.
let bin_coeff_ntt_square_min_words = 3584

///|
/// Operand length, in 64-bit limbs, from which a square that is not an NTT or
/// Karatsuba square runs Toom-3 instead of the general product.
let bin_coeff_square_toom3_min_words = 384

///|
/// Operand length, in 64-bit limbs, below which a square that does not take the
/// word Karatsuba square runs the schoolbook square, and above which it runs the
/// general product.
let bin_coeff_square_recursive_min_words = 256

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
/// 32-bit limbs (never on this target).
let bin_coeff_limb32_min_words : Int32 = 1073741824

///|
/// Whether Knuth's division runs on 64-bit digits. True on every target: measured
/// faster on Wasm (1.3 and 3.3 times at 2,048 and 8,192 bits) and Wasm-GC (1.9 and
/// 3.3 times) as well as on Native (commit 27989825, issue 328), although a 64-bit
/// digit step costs four `i64.mul` there.
let bin_coeff_knuth_words_enabled : Bool = true

///|
/// Divisor length, in 64-bit limbs, up to which the Burnikel-Ziegler
/// recursion ends in Knuth's algorithm.
let bin_coeff_bz_leaf_words = 64

///|
/// Divisor length, in 64-bit limbs, from which division uses Newton's
/// reciprocal (never selected: the routine stays for tests).
let bin_coeff_newton_division_min_words = 536870912

///|
/// Whether the integer square roots of up to 256 bits use the word kernels
/// (`bin_coeff_sqrt_words_nonjs.mbt`) instead of the restoring loops.
let bin_coeff_sqrt_words_enabled = true

///|
/// Limb count (64-bit limbs) below which the half-product schoolbook square
/// beats the Karatsuba square step of the word-range squaring.
let bin_coeff_words_square_cutoff : Int32 = 36

///|
/// Whether squaring runs the word-range Karatsuba square
/// (`bin_coeff_words_sqr_scratch`) between the schoolbook square and the NTT.
let bin_coeff_square_words_enabled = true

///|
/// Number of 64-bit limbs from which `Coeff::to_radix_string` formats by
/// divide and conquer instead of dividing a copy of the limbs chunk by chunk.
let bin_coeff_radix_format_dc_words = 3072

///|
/// Number of digit chunks from which `Coeff::parse` combines chunks by
/// divide and conquer instead of accumulating them in place.
let bin_coeff_radix_parse_dc_chunks = 4608

///|
/// Whether the NTT converts operands and products on the 32-bit view of the
/// storage (Wasm: measured faster than 64-bit limbs there, 300,000-bit product
/// on Wasm-GC) instead of on 64-bit limbs.
let bin_coeff_ntt_limb32_conversion = false

///|
/// Shortest short product, in limbs of the extended precision: below it the
/// setup (two shifted operands, the product array, the rounding window) costs
/// more than the rows save. Measured with the C rows (instructions per `mul`, two-count method): the short product over the schoolbook and Karatsuba product 1.05 at 17 limbs, 0.94 at 21, 0.86 at 25, 0.71 at 65, 0.84 at 129, 0.94 at 193, 1.02 at 257.
/// With `LUNA_FLOATING_PORTABLE` set the rows are the portable loops and the
/// portable limits (13 and 64 limbs) apply.
let bin_coeff_short_product_min_limbs : Int32 = if bin_limbs_mode != 0 {
  20
} else {
  13
}

///|
/// Longest short product, in limbs: above it the Karatsuba product is as cheap.
/// See the minimum.
let bin_coeff_short_product_max_limbs : Int32 = if bin_limbs_mode != 0 {
  192
} else {
  64
}

///|
/// Divisor length, in 64-bit limbs, from which division uses Burnikel-Ziegler.
/// The crossover with Knuth's division depends on the row tier, because the
/// Knuth row costs 3 to 4 instructions per limb pair on the assembly rows, 11
/// on the C rows and 20 on the portable loops while the rest of the recursive
/// division is the same. Measured (instructions per division of 2n by n limbs,
/// Burnikel-Ziegler over Knuth, `j * 2^k` padding, an 8-limb grid around each
/// crossover): assembly rows 1.41 at 256 limbs, 1.10 at 640, 1.02 at 736 and
/// 0.98 at 744, 0.96 at 752, 0.92 at 800, 0.73 at 1,500; C rows 1.04 at 256,
/// 0.98 at 320, 1.04 at 328, 1.02 at 352, 0.94 at 360, 0.90 at 392, 0.71 at
/// 704; portable loops 1.03 at 184, 1.01 at 192, 0.93 at 208, 0.90 at 232, 0.60
/// at 704. Each value keeps every measured n within 3 percent of the better
/// algorithm of its tier (the limbs of the dividend of a `BinFloat` division
/// are `2n + 1`, one more than the measured shape, which costs the recursion a
/// second block when the divisor needs no padding: the assembly and C values
/// are therefore taken a step above their crossovers). BZ's cost is products
/// (Karatsuba and the product limits), so the grid must be measured again when
/// they move.
let bin_coeff_bz_division_min_words : Int32 = match bin_limbs_mode {
  2 => 752
  1 => 352
  _ => 208
}
