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
/// Smallest product, in limbs, that the NTT multiplies, besides the limit on
/// the shorter operand. The NTT costs the same for every product below a power
/// of two of its transform length (about 39M, 83M to 85M, 172M to 176M and
/// 373M to 380M instructions at 8,192, 16,384 to 30,720, 32,768 to 61,440 and
/// 49,152 limbs of product), while Toom-3 and Karatsuba grow smoothly, so with
/// fast rows the product, not the shorter operand, decides. Per row
/// implementation, from `Coeff::mul` of `n x n` and unbalanced products
/// (instructions per call, two-count method, median of five runs): the
/// assembly rows beat the NTT up to 14,336 limbs (0.40 to 0.86 of its count at
/// 5,120 to 14,336 limbs, equal at 15,360) and the C rows up to 7,168 limbs
/// (0.52 to 0.86); the portable loops keep the limit alone (the NTT is cheaper
/// from 4,096 limbs there). The limit on the shorter operand stays the whole
/// rule on the other targets (`coeff_limbs_other_nonjs.mbt`).
let bin_coeff_ntt_mul_min_product_words : Int32 = if bin_limbs_mode == 2 {
  30720
} else if bin_limbs_mode == 1 {
  15360
} else {
  0
}

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
/// Karatsuba step of the word-range multiplication. Per row implementation
/// (instructions per `Coeff::mul`, two-count method, `n x n` limbs): with the
/// assembly rows the schoolbook product is cheaper up to about 48 limbs
/// (8,040 against 9,237 at 32, 27,481 against 30,001 at 64 limbs with one
/// level instead of two); with the C rows and the portable loops 32 stays the
/// optimum.
let bin_coeff_words_karatsuba_cutoff : Int32 = if bin_limbs_mode == 2 {
  48
} else {
  32
}

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
/// beats the Karatsuba square step of the word-range squaring. Per row
/// implementation (instructions per `Coeff::square`, two-count method): the
/// assembly rows make the schoolbook square cheaper up to about 96 limbs
/// (18,043 against 20,129 at 64 limbs, 37,010 against 43,828 at 96 with the
/// old 36), the C rows up to 64 (40,412 to 37,433 at 80 limbs); the portable
/// loops keep 36.
let bin_coeff_words_square_cutoff : Int32 = if bin_limbs_mode == 2 {
  96
} else if bin_limbs_mode == 1 {
  64
} else {
  36
}

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
/// more than the rows save. Per row implementation, from the short product over
/// the schoolbook and Karatsuba product (instructions per `mul`, two-count
/// method). Assembly rows: 1.23 at 17 limbs, 1.05 at 25, 1.00 at 27, 1.03 at
/// 29, 0.93 at 31, 0.81 at 33, 0.71 at 65, 0.83 at 257, 0.92 at 321, 0.98 at
/// 385, 1.01 at 513; the limits are 31 and 384. C rows: 1.03 at 17, 1.00 at
/// 21, 0.90 at 25, 0.78 at 33, 0.84 at 129, 0.93 at 193, 1.01 at 257, 1.09 at
/// 321; the limits stay 20 and 192. With `LUNA_FLOATING_PORTABLE` set the rows
/// are the portable loops and the portable limits (13 and 64 limbs) apply.
let bin_coeff_short_product_min_limbs : Int32 = if bin_limbs_mode == 2 {
  31
} else if bin_limbs_mode == 1 {
  20
} else {
  13
}

///|
/// Longest short product, in limbs: above it the Karatsuba product is as cheap.
/// See the minimum.
let bin_coeff_short_product_max_limbs : Int32 = if bin_limbs_mode == 2 {
  384
} else if bin_limbs_mode == 1 {
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
/// algorithm of its tier (the limbs of the dividend of a `Binary` division
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
