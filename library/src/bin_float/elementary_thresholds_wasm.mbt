///|
/// Working precision from which the bit-burst enclosure of `exp` replaces the
/// series (measured crossover on this target).
let binary_exp_burst_min_precision = 1088

///|
/// Working precision up to which the table-based `exp` kernel is the first choice
/// (measured crossover against the bit-burst and series paths on this target).
let binary_exp_table_max_precision = 2048

///|
/// Working precision from which the verified Newton step replaces the series for
/// `ln` of a number in (1, 2] (measured crossover on this target).
let binary_ln_burst_min_precision = 1280

///|
/// Working precision from which the bit-burst enclosure of `sin` and `cos`
/// replaces the reduction and the series (measured crossover on this target).
let binary_trig_burst_min_precision = 2112
