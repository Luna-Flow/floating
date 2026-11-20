///|
/// Working precision from which the bit-burst enclosure of `exp` replaces the
/// series (measured crossover on this target).
let binary_exp_burst_min_precision = 640

///|
/// Working precision up to which the table-based `exp` kernel is the first choice
/// (measured crossover against the bit-burst and series paths on this target).
let binary_exp_table_max_precision = 1536

///|
/// Working precision from which the verified Newton step replaces the series for
/// `ln` of a number in (1, 2] (measured crossover on this target).
let binary_ln_burst_min_precision = 576

///|
/// Working precision from which the bit-burst enclosure of `sin` and `cos`
/// replaces the reduction and the series (measured crossover on this target).
let binary_trig_burst_min_precision = 640

///|
/// Working precision from which the outermost `ln` call starts with a Newton
/// step (not measured on this target: equal to the nested threshold).
let binary_ln_entry_min_precision : Int32 = binary_ln_burst_min_precision
