// Generates the MPFR 4.2.2 oracle corpora for BinFloat decimal character
// conversion (IEEE 754-2019 5.12):
//
//   generate_mpfr_decimal_string_oracle strtofr [cases-per-cell] [seed]
//     mpfr_strtofr: decimal text to a binary value of a given precision under
//     every rounding direction, including exact halfway inputs, inputs a hair
//     above and below a halfway point, long mantissas and huge exponents.
//
//   generate_mpfr_decimal_string_oracle output [cases-per-cell] [seed]
//     mpfr_get_str: a binary value printed with a fixed number of significant
//     digits, and the shortest digit count that reads back exactly.
//
// Both write space separated rows to standard output; see
// testdata/bin_float/README.md for the formats. Build with
// `cc -O1 -o generator tools/generate_mpfr_decimal_string_oracle.c -lmpfr -lgmp`.
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <gmp.h>
#include <mpfr.h>

static const mpfr_prec_t precisions[] = {11, 24, 53, 113, 200};
static const mpfr_rnd_t roundings[] = {
    MPFR_RNDN, MPFR_RNDN, MPFR_RNDZ, MPFR_RNDU, MPFR_RNDD, MPFR_RNDA,
};
static const char *rounding_names[] = {"n", "na", "z", "u", "d", "a"};
#define PRECISION_COUNT (sizeof(precisions) / sizeof(precisions[0]))
#define ROUNDING_COUNT (sizeof(roundings) / sizeof(roundings[0]))

static uint64_t next_random(uint64_t *state) {
  *state = *state * UINT64_C(6364136223846793005) +
           UINT64_C(1442695040888963407);
  return *state >> 11;
}

static long random_range(uint64_t *state, long low, long high) {
  return low + (long)(next_random(state) % (uint64_t)(high - low + 1));
}

static void print_hex(const mpfr_t value) {
  if (mpfr_nan_p(value)) {
    fputs("nan", stdout);
    return;
  }
  if (mpfr_inf_p(value)) {
    fputs(mpfr_signbit(value) ? "-inf" : "inf", stdout);
    return;
  }
  mpz_t coefficient;
  mpz_init(coefficient);
  mpfr_exp_t exponent = mpfr_get_z_2exp(coefficient, value);
  if (mpz_sgn(coefficient) < 0) {
    fputs("-0x", stdout);
    mpz_neg(coefficient, coefficient);
  } else {
    if (mpfr_zero_p(value) && mpfr_signbit(value)) fputc('-', stdout);
    fputs("0x", stdout);
  }
  mpz_out_str(stdout, 16, coefficient);
  printf("p%ld", (long)exponent);
  mpz_clear(coefficient);
}

// ---------------------------------------------------------------- strtofr --

static void emit_strtofr(mpfr_t output, size_t precision_index,
                         size_t rounding_index, const char *text) {
  mpfr_set_prec(output, precisions[precision_index]);
  mpfr_clear_flags();
  char *end = NULL;
  int ternary;
  if (rounding_index == 1) {
    mpfr_round_nearest_away_begin(output);
    ternary = mpfr_strtofr(output, text, &end, 10, MPFR_RNDN);
    ternary = mpfr_round_nearest_away_end(output, ternary);
  } else {
    ternary = mpfr_strtofr(output, text, &end, 10, roundings[rounding_index]);
  }
  if (end == NULL || *end != '\0') {
    fprintf(stderr, "strtofr did not consume %s\n", text);
    exit(2);
  }
  printf("%ld %s %s ", (long)precisions[precision_index],
         rounding_names[rounding_index], text);
  print_hex(output);
  printf(" %d %d %d\n", ternary != 0, mpfr_overflow_p() != 0,
         mpfr_underflow_p() != 0);
}

// A decimal literal with sign, digits, optional fraction and optional exponent
// whose value stays well inside the binary exponent range, so that MPFR (no
// subnormals: results below 2^(emin-1) flush) and BinFloat (IEEE subnormals)
// agree on every rounding direction.
static void random_literal(uint64_t *state, char *buffer, size_t size,
                           long mantissa_digits) {
  size_t used = 0;
  if (random_range(state, 0, 9) < 3) buffer[used++] = '-';
  long integer_digits = random_range(state, 0, mantissa_digits);
  long fraction_digits = mantissa_digits - integer_digits;
  if (integer_digits == 0) buffer[used++] = '0';
  for (long i = 0; i < integer_digits; ++i) {
    long digit = random_range(state, i == 0 ? 1 : 0, 9);
    buffer[used++] = (char)('0' + digit);
  }
  if (fraction_digits > 0) {
    buffer[used++] = '.';
    for (long i = 0; i < fraction_digits; ++i) {
      buffer[used++] = (char)('0' + random_range(state, 0, 9));
    }
  }
  long kind = random_range(state, 0, 9);
  long exponent = 0;
  int has_exponent = 1;
  if (kind <= 3) {
    has_exponent = 0;
  } else if (kind == 4) {
    exponent = random_range(state, -20, 20);
  } else if (kind == 5) {
    exponent = random_range(state, -400, 400);
  } else if (kind == 6) {
    exponent = random_range(state, -40000, 40000);
  } else if (kind == 7) {
    exponent = random_range(state, 100000, 300000000);
    if (random_range(state, 0, 1)) exponent = -exponent;
  } else {
    exponent = random_range(state, -1000, 1000);
  }
  if (has_exponent) {
    buffer[used++] = (random_range(state, 0, 1) ? 'e' : 'E');
    used += (size_t)snprintf(buffer + used, size - used, "%ld", exponent);
  }
  buffer[used] = '\0';
}

// Writes the exact decimal expansion of num * 2^binary_exponent, optionally
// perturbed by one unit in the last place (+1 or -1 at a position far below
// the neighbouring binary values), into buffer.
static void exact_literal(char *buffer, size_t size, const mpz_t num,
                          long binary_exponent, int perturbation, int negative) {
  mpz_t scaled;
  mpz_init(scaled);
  long fraction_digits = 0;
  if (binary_exponent >= 0) {
    mpz_mul_2exp(scaled, num, (mp_bitcnt_t)binary_exponent);
  } else {
    mpz_t power;
    mpz_init(power);
    fraction_digits = -binary_exponent;
    mpz_ui_pow_ui(power, 5, (unsigned long)fraction_digits);
    mpz_mul(scaled, num, power);
    mpz_clear(power);
  }
  if (perturbation != 0) {
    // Move one more decimal place down and add or subtract one unit there.
    mpz_mul_ui(scaled, scaled, 10);
    fraction_digits += 1;
    if (perturbation > 0) {
      mpz_add_ui(scaled, scaled, 1);
    } else {
      mpz_sub_ui(scaled, scaled, 1);
    }
  }
  char *digits = mpz_get_str(NULL, 10, scaled);
  size_t length = strlen(digits);
  size_t used = 0;
  if (negative) buffer[used++] = '-';
  if ((long)length <= fraction_digits) {
    used += (size_t)snprintf(buffer + used, size - used, "0.");
    for (long i = 0; i < fraction_digits - (long)length; ++i) buffer[used++] = '0';
    memcpy(buffer + used, digits, length);
    used += length;
  } else {
    size_t integer_length = length - (size_t)fraction_digits;
    memcpy(buffer + used, digits, integer_length);
    used += integer_length;
    if (fraction_digits > 0) {
      buffer[used++] = '.';
      memcpy(buffer + used, digits + integer_length, (size_t)fraction_digits);
      used += (size_t)fraction_digits;
    }
  }
  buffer[used] = '\0';
  free(digits);
  mpz_clear(scaled);
}

static int generate_strtofr(long cases_per_cell, uint64_t seed) {
  printf("# mpfr-strtofr-v1 mpfr=%s cases-per-cell=%ld seed=%llu\n",
         mpfr_get_version(), cases_per_cell, (unsigned long long)seed);
  puts("# precision rounding input expected inexact overflow underflow");
  mpfr_t output;
  mpfr_init2(output, 2);
  uint64_t state = seed;
  static char buffer[4096];
  mpz_t num;
  mpz_init(num);
  for (size_t p = 0; p < PRECISION_COUNT; ++p) {
    mpfr_prec_t precision = precisions[p];
    for (size_t r = 0; r < ROUNDING_COUNT; ++r) {
      for (long i = 0; i < cases_per_cell; ++i) {
        random_literal(&state, buffer, sizeof(buffer), random_range(&state, 1, 22));
        emit_strtofr(output, p, r, buffer);
      }
      for (long i = 0; i < (cases_per_cell + 7) / 8; ++i) {
        // Long mantissas: the decision between two neighbours must use the
        // whole digit string.
        long digits[] = {60, 120, 400};
        random_literal(&state, buffer, sizeof(buffer), digits[i % 3]);
        emit_strtofr(output, p, r, buffer);
      }
      for (long i = 0; i < (cases_per_cell + 3) / 4; ++i) {
        // Exact halfway points between adjacent p-bit values and decimal
        // strings one unit above and below them.
        // Build a (p + 1)-bit odd integer from the generator state.
        mpz_set_ui(num, 1);
        for (mpfr_prec_t bit = 1; bit < precision; ++bit) {
          mpz_mul_2exp(num, num, 1);
          if (random_range(&state, 0, 1)) mpz_add_ui(num, num, 1);
        }
        mpz_mul_2exp(num, num, 1);
        mpz_add_ui(num, num, 1);  // 2m + 1: a midpoint numerator
        long exponent2 = random_range(&state, -70, 70) - 1;
        int negative = random_range(&state, 0, 4) == 0;
        for (int perturbation = -1; perturbation <= 1; ++perturbation) {
          exact_literal(buffer, sizeof(buffer), num, exponent2, perturbation,
                        negative);
          emit_strtofr(output, p, r, buffer);
        }
      }
    }
  }
  // Specials and range limits. MPFR writes a value as 0.1xxx * 2^e with
  // emax = 2^30 - 1, so its largest finite value has the leading bit 2^30 - 2,
  // one binade below BinFloat's implementation limit (leading bit 2^30 - 1,
  // see binary_implementation_e_max). The two agree on every input that
  // overflows to infinity, so the rows above the limit are only emitted for
  // the directions that deliver infinity, and the finite rows stay well below
  // the top binade.
  static const char *fixed[] = {
      "0",
      "-0",
      "0e999999999",
      "-0.000e5",
      "+5",
      "1",
      "0.1",
      "-0.1",
      "123456789012345678901234567890e-30",
      "1e323228495",
      "-1e323228495",
  };
  static const char *overflowing[] = {"1e323228497", "9e323228496",
                                      "1e400000000", "7.5e999999999"};
  static const size_t to_infinity_positive[] = {0, 1, 3, 5};
  static const size_t to_infinity_negative[] = {0, 1, 4, 5};
  for (size_t p = 0; p < PRECISION_COUNT; ++p) {
    if (precisions[p] != 24 && precisions[p] != 53 && precisions[p] != 113) continue;
    for (size_t r = 0; r < ROUNDING_COUNT; ++r) {
      for (size_t i = 0; i < sizeof(fixed) / sizeof(fixed[0]); ++i) {
        emit_strtofr(output, p, r, fixed[i]);
      }
    }
    for (size_t i = 0; i < sizeof(overflowing) / sizeof(overflowing[0]); ++i) {
      char negative_text[64];
      snprintf(negative_text, sizeof(negative_text), "-%s", overflowing[i]);
      for (size_t k = 0; k < 4; ++k) {
        emit_strtofr(output, p, to_infinity_positive[k], overflowing[i]);
        emit_strtofr(output, p, to_infinity_negative[k], negative_text);
      }
    }
  }
  // Far below the smallest positive value MPFR flushes to zero (no
  // subnormals) in the rounding directions that go towards zero; BinFloat
  // rounds to zero as well. Away-from-zero directions are left out because
  // MPFR returns its smallest value and IEEE formats a subnormal.
  static const char *deep[] = {"1e-400000000", "3.7e-500000000",
                               "1e-323228600"};
  for (size_t p = 0; p < PRECISION_COUNT; ++p) {
    if (precisions[p] != 24 && precisions[p] != 53 && precisions[p] != 113) continue;
    for (size_t i = 0; i < sizeof(deep) / sizeof(deep[0]); ++i) {
      char negative_text[64];
      snprintf(negative_text, sizeof(negative_text), "-%s", deep[i]);
      static const size_t toward_zero_positive[] = {0, 1, 2, 4};
      static const size_t toward_zero_negative[] = {0, 1, 2, 3};
      for (size_t k = 0; k < 4; ++k) {
        emit_strtofr(output, p, toward_zero_positive[k], deep[i]);
        emit_strtofr(output, p, toward_zero_negative[k], negative_text);
      }
    }
  }
  mpz_clear(num);
  mpfr_clear(output);
  return 0;
}

// ---------------------------------------------------------------- output ---

static void random_binary(mpfr_t value, uint64_t *state, mpfr_prec_t precision,
                          long exponent_limit) {
  mpz_t coefficient;
  mpz_init(coefficient);
  mpz_set_ui(coefficient, 1);
  for (mpfr_prec_t bit = 1; bit < precision; ++bit) {
    mpz_mul_2exp(coefficient, coefficient, 1);
    if (random_range(state, 0, 1)) mpz_add_ui(coefficient, coefficient, 1);
  }
  if (random_range(state, 0, 3) == 0) {
    // Trailing zero bits: values that are short in binary.
    mp_bitcnt_t shift = (mp_bitcnt_t)random_range(state, 1, precision - 1);
    mpz_tdiv_q_2exp(coefficient, coefficient, shift);
    if (mpz_sgn(coefficient) == 0) mpz_set_ui(coefficient, 1);
  }
  long exponent = random_range(state, -exponent_limit, exponent_limit);
  mpfr_set_z_2exp(value, coefficient, exponent, MPFR_RNDN);
  if (random_range(state, 0, 4) == 0) mpfr_neg(value, value, MPFR_RNDN);
  mpz_clear(coefficient);
}

// Whether digits * 10^(exponent - length) equals |value| exactly.
static int decimal_is_exact(const mpfr_t value, const char *digits,
                            mpfr_exp_t exponent) {
  mpz_t coefficient, decimal, left, right;
  mpz_init(coefficient);
  mpz_init(decimal);
  mpz_init(left);
  mpz_init(right);
  mpfr_exp_t binary = mpfr_get_z_2exp(coefficient, value);
  mpz_abs(coefficient, coefficient);
  mpz_set_str(decimal, digits, 10);
  long scale = (long)exponent - (long)strlen(digits);  // value = decimal * 10^scale
  // coefficient * 2^binary == decimal * 10^scale
  mpz_set(left, coefficient);
  mpz_set(right, decimal);
  if (binary >= 0) {
    mpz_mul_2exp(left, left, (mp_bitcnt_t)binary);
  } else {
    mpz_mul_2exp(right, right, (mp_bitcnt_t)(-binary));
  }
  mpz_t power;
  mpz_init(power);
  if (scale >= 0) {
    mpz_ui_pow_ui(power, 10, (unsigned long)scale);
    mpz_mul(right, right, power);
  } else {
    mpz_ui_pow_ui(power, 10, (unsigned long)(-scale));
    mpz_mul(left, left, power);
  }
  int equal = mpz_cmp(left, right) == 0;
  mpz_clear(power);
  mpz_clear(right);
  mpz_clear(left);
  mpz_clear(decimal);
  mpz_clear(coefficient);
  return equal;
}

static void emit_fixed(const mpfr_t value, long digits, size_t rounding_index) {
  mpfr_exp_t exponent;
  char *text = mpfr_get_str(NULL, &exponent, 10, (size_t)digits, value,
                            roundings[rounding_index]);
  const char *unsigned_digits = text[0] == '-' ? text + 1 : text;
  printf("fixed %ld %ld %s ", digits, (long)mpfr_get_prec(value),
         rounding_names[rounding_index]);
  print_hex(value);
  printf(" %s %ld %d\n", unsigned_digits, (long)exponent - 1,
         !decimal_is_exact(value, unsigned_digits, exponent));
  mpfr_free_str(text);
}

// The fewest significant digits n such that the n-digit decimal below or above
// the value (or the value itself) reads back, rounding to nearest, as exactly
// this value at the same precision. Any shorter decimal that reads back lies
// between these two neighbours, and the interval of values that read back is
// convex, so one of them reads back too.
static long shortest_digits(const mpfr_t value) {
  mpfr_t magnitude, parsed;
  mpfr_prec_t precision = mpfr_get_prec(value);
  mpfr_init2(magnitude, precision);
  mpfr_init2(parsed, precision);
  mpfr_abs(magnitude, value, MPFR_RNDN);
  long limit = (long)(precision * 0.30102999566398120) + 3;
  for (long digits = 1; digits <= limit; ++digits) {
    for (int direction = 0; direction < 2; ++direction) {
      mpfr_exp_t exponent;
      char *text = mpfr_get_str(NULL, &exponent, 10, (size_t)digits, magnitude,
                                direction == 0 ? MPFR_RNDD : MPFR_RNDU);
      char literal[1024];
      snprintf(literal, sizeof(literal), "0.%se%ld", text, (long)exponent);
      mpfr_free_str(text);
      mpfr_strtofr(parsed, literal, NULL, 10, MPFR_RNDN);
      if (mpfr_equal_p(parsed, magnitude)) {
        mpfr_clear(parsed);
        mpfr_clear(magnitude);
        return digits;
      }
    }
  }
  fprintf(stderr, "no shortest digit count found\n");
  exit(2);
}

static int generate_output(long cases_per_cell, uint64_t seed) {
  printf("# mpfr-decimal-output-v1 mpfr=%s cases-per-cell=%ld seed=%llu\n",
         mpfr_get_version(), cases_per_cell, (unsigned long long)seed);
  puts("# fixed digits precision rounding value expected_digits expected_exponent10 inexact");
  puts("# shortest precision value expected_digit_count");
  static const long digit_counts[] = {1, 2, 3, 5, 8, 17, 20, 34, 40, 60};
  uint64_t state = seed;
  mpfr_t value;
  mpfr_init2(value, 2);
  for (size_t p = 0; p < PRECISION_COUNT; ++p) {
    mpfr_set_prec(value, precisions[p]);
    for (size_t r = 0; r < ROUNDING_COUNT; ++r) {
      if (r == 1) continue;  // mpfr_get_str has no nearest-away direction
      for (size_t d = 0; d < sizeof(digit_counts) / sizeof(digit_counts[0]); ++d) {
        for (long i = 0; i < cases_per_cell; ++i) {
          random_binary(value, &state, precisions[p], i % 4 == 3 ? 20000 : 300);
          emit_fixed(value, digit_counts[d], r);
        }
      }
    }
    for (long i = 0; i < cases_per_cell * 4; ++i) {
      random_binary(value, &state, precisions[p], i % 4 == 3 ? 20000 : 300);
      printf("shortest %ld ", (long)precisions[p]);
      print_hex(value);
      printf(" %ld\n", shortest_digits(value));
    }
  }
  // Exact ties: the dropped digits are 5 followed by zeros, so the nearest
  // direction goes to the even digit and the away direction rounds up.
  static const char *ties[] = {"0x5p-1",  "0x3p-1", "0x7p-1",  "0x19p-1",
                               "0x1p-3",  "0x3p-3", "0x5p-3",  "0x1p-1",
                               "-0x5p-1", "0x15p-1", "0x1fp-6", "0x271p-1"};
  static const long tie_digits[] = {1, 1, 1, 2, 2, 2, 2, 0, 1, 2, 3, 3};
  mpfr_set_prec(value, 53);
  for (size_t i = 0; i < sizeof(ties) / sizeof(ties[0]); ++i) {
    mpfr_set_str(value, ties[i], 16, MPFR_RNDN);
    for (size_t r = 0; r < ROUNDING_COUNT; ++r) {
      if (r == 1) continue;
      long digits = tie_digits[i];
      if (digits == 0) digits = 1;
      emit_fixed(value, digits, r);
    }
  }
  mpfr_clear(value);
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2 || argc > 4) {
    fprintf(stderr, "usage: %s strtofr|output [cases-per-cell] [seed]\n",
            argv[0]);
    return 2;
  }
  long cases_per_cell = 24;
  uint64_t seed = UINT64_C(20261014);
  char *end = NULL;
  if (argc >= 3) {
    errno = 0;
    cases_per_cell = strtol(argv[2], &end, 10);
    if (errno != 0 || *end != '\0' || cases_per_cell <= 0) return 2;
  }
  if (argc >= 4) {
    errno = 0;
    seed = (uint64_t)strtoull(argv[3], &end, 10);
    if (errno != 0 || *end != '\0' || seed == 0) return 2;
  }
  if (strcmp(argv[1], "strtofr") == 0) return generate_strtofr(cases_per_cell, seed);
  if (strcmp(argv[1], "output") == 0) return generate_output(cases_per_cell, seed);
  fprintf(stderr, "unknown corpus %s\n", argv[1]);
  return 2;
}
