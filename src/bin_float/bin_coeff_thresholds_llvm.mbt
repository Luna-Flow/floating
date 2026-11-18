///|
let bin_coeff_karatsuba_threshold = 96

///|
let bin_coeff_toom3_threshold = 2048

///|
let bin_coeff_ntt_mul_threshold = 2048

///|
let bin_coeff_ntt_square_threshold = 768

///|
let bin_coeff_square_recursive_threshold = 768

///|
let bin_coeff_sqrt_dc_base_bits = 256

///|
/// Working precision from which the bit-burst enclosure of `exp` replaces the
/// series (measured crossover on this target).
let binary_exp_burst_min_precision = 1024
