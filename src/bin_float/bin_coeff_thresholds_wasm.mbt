///|
let bin_coeff_karatsuba_threshold = 96

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
let binary_exp_burst_min_precision = 640
