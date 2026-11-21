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
/// more than the rows save. Measured with the portable rows on Native only (the crossover at 13 limbs and the gain 0.75 at 33 limbs); not measured on this target, and not above 64 limbs with the portable rows.
let bin_coeff_short_product_min_limbs : Int32 = 13

///|
/// Longest short product, in limbs: above it the Karatsuba product is as cheap.
/// See the minimum.
let bin_coeff_short_product_max_limbs : Int32 = 64
