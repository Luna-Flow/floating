// Seeded random differential oracle for BinFloat against GNU MPFR.
//
//   generate_mpfr_random_oracle <family> <seed> <start> <count>
//   generate_mpfr_random_oracle eval            (rows on stdin, expected "?")
//   generate_mpfr_random_oracle families
//
// Writes `mpfr-random-v1` rows (see testdata/bin_float/README.md). Case I of
// family F under seed S is a pure function of (S, F, I): the generator seeds a
// SplitMix64 stream from the triple, so `family seed I 1` reproduces one row
// of a million-row run. Every row carries the id `S.F.I`.
//
// Round-to-nearest-away goes through MPFR's mpfr_round_nearest_away_begin/end
// wrapper. The exponent range of each row is set on MPFR so that it equals the
// BinaryContext range, and results are put through mpfr_subnormalize, which
// emulates IEEE 754 gradual underflow (MPFR itself has no subnormals). The
// underflow flag is derived from the IEEE 754-2019 7.5 definition (tiny and
// inexact) for both tininess-detection rules, because MPFR's own flag follows
// a different convention.
//
// Build: cc -O2 -o generator tools/generate_mpfr_random_oracle.c -lmpfr -lgmp
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <gmp.h>
#include <mpfr.h>

typedef uint64_t u64;

// ------------------------------------------------------------------- RNG ---

static u64 splitmix_next(u64 *state) {
  u64 z = (*state += UINT64_C(0x9E3779B97F4A7C15));
  z = (z ^ (z >> 30)) * UINT64_C(0xBF58476D1CE4E5B9);
  z = (z ^ (z >> 27)) * UINT64_C(0x94D049BB133111EB);
  return z ^ (z >> 31);
}

static u64 mix64(u64 value) {
  u64 state = value;
  return splitmix_next(&state);
}

typedef struct {
  u64 state;
} rng_t;

static u64 fnv1a(const char *text) {
  u64 hash = UINT64_C(0xcbf29ce484222325);
  for (; *text; ++text) {
    hash ^= (unsigned char)*text;
    hash *= UINT64_C(0x100000001b3);
  }
  return hash;
}

static void rng_seed(rng_t *rng, u64 seed, u64 family, u64 index) {
  u64 state = mix64(seed);
  state = mix64(state ^ (family * UINT64_C(0xD6E8FEB86659FD93)));
  state = mix64(state ^ (index * UINT64_C(0xA0761D6478BD642F) + 0x1234567));
  rng->state = state;
}

static u64 rnd64(rng_t *rng) { return splitmix_next(&rng->state); }

// Uniform in [low, high].
static long rnd_range(rng_t *rng, long low, long high) {
  if (high <= low) return low;
  u64 span = (u64)(high - low) + 1;
  return low + (long)(rnd64(rng) % span);
}

static int chance(rng_t *rng, int numerator, int denominator) {
  return (long)(rnd64(rng) % (u64)denominator) < numerator;
}

static int bit_length(u64 value) {
  int length = 0;
  while (value) {
    ++length;
    value >>= 1;
  }
  return length;
}

// Log-uniform in [low, high] (low >= 1) using integer arithmetic only, so the
// stream does not depend on libm.
static long rnd_log(rng_t *rng, long low, long high) {
  int lo_bits = bit_length((u64)low);
  int hi_bits = bit_length((u64)high);
  int bits = (int)rnd_range(rng, lo_bits, hi_bits);
  long lower = bits == 1 ? 1 : (long)1 << (bits - 1);
  long upper = ((long)1 << bits) - 1;
  if (lower < low) lower = low;
  if (upper > high) upper = high;
  return rnd_range(rng, lower, upper);
}

// ----------------------------------------------------------------- model ---

// The implementation range of the library, written here on purpose: the oracle
// keeps its own copy of the number so that it stays independent of the library
// (a change of the library constant must change this one, and the test
// `tooling/src/consistency/oracle_constants_wbtest.mbt` and
// `tools/oracle_constants_test.py` fail until it does). The value is the
// decision of the library: the exponent of the leading bit of a stored value
// is below 2^30 (`binary_implementation_e_max`), and `emin = 1 - emax`
// (IEEE 754-2019 3.3).
#define IMPL_EMAX 1073741823L
#define IMPL_EMIN (1 - IMPL_EMAX)
// The largest precision this oracle draws; it is a cap of the oracle program
// (time and memory of the MPFR evaluation), not a limit of the library
// (`binary_precision_max` is 268435456).
#define PREC_MAX 10000L

typedef enum {
  K_ARITH,
  K_ELEM,
  K_STRTOFR,
  K_GETSTR,
  K_SHORTEST,
} kind_t;

typedef struct {
  const char *name;
  kind_t kind;
  int arity;
} op_t;

static const op_t operations[] = {
    {"add", K_ARITH, 2},    {"sub", K_ARITH, 2},   {"mul", K_ARITH, 2},
    {"div", K_ARITH, 2},    {"sqrt", K_ARITH, 1},  {"fma", K_ARITH, 3},
    {"strtofr", K_STRTOFR, 0}, {"getstr", K_GETSTR, 1},
    {"shortest", K_SHORTEST, 1},
    {"exp", K_ELEM, 1},     {"exp2", K_ELEM, 1},   {"exp10", K_ELEM, 1},
    {"expm1", K_ELEM, 1},   {"ln", K_ELEM, 1},     {"log2", K_ELEM, 1},
    {"log10", K_ELEM, 1},   {"log1p", K_ELEM, 1},  {"rootn", K_ELEM, 1},
    {"pown", K_ELEM, 1},    {"pow", K_ELEM, 2},    {"hypot", K_ELEM, 2},
    {"sin", K_ELEM, 1},     {"cos", K_ELEM, 1},    {"tan", K_ELEM, 1},
    {"sinpi", K_ELEM, 1},   {"cospi", K_ELEM, 1},  {"tanpi", K_ELEM, 1},
    {"asin", K_ELEM, 1},    {"acos", K_ELEM, 1},   {"atan", K_ELEM, 1},
    {"atan2", K_ELEM, 2},   {"sinh", K_ELEM, 1},   {"cosh", K_ELEM, 1},
    {"tanh", K_ELEM, 1},    {"asinh", K_ELEM, 1},  {"acosh", K_ELEM, 1},
    {"atanh", K_ELEM, 1},
    // Added after the first campaign; the "elem" family stays on the entries
    // above so that its rows do not change, the new ones are "elem2".
    {"exp2m1", K_ELEM, 1},  {"exp10m1", K_ELEM, 1},
    {"log2p1", K_ELEM, 1},  {"log10p1", K_ELEM, 1},
    // The family "elem3".
    {"rsqrt", K_ELEM, 1},   {"compound", K_ELEM, 1}, {"powr", K_ELEM, 2},
    // The family "elem4".
    {"asinpi", K_ELEM, 1},  {"acospi", K_ELEM, 1},   {"atanpi", K_ELEM, 1},
    {"atan2pi", K_ELEM, 2},
};
#define OP_COUNT (sizeof(operations) / sizeof(operations[0]))
#define FIRST_ELEM 9
#define LEGACY_OP_COUNT 37
#define ELEM2_END 41
#define ELEM3_END 44

static const char *rounding_names[] = {"n", "na", "z", "u", "d"};
static const mpfr_rnd_t rounding_modes[] = {
    MPFR_RNDN, MPFR_RNDN, MPFR_RNDZ, MPFR_RNDU, MPFR_RNDD,
};
#define R_NA 1

enum { F_INEXACT = 1, F_OVERFLOW = 2, F_UNDERFLOW = 4, F_INVALID = 8, F_DIVZERO = 16 };

typedef struct {
  char id[160];
  const op_t *op;
  int rounding;
  long precision;
  int bounded;
  long emin, emax;
  int before;  // tininess detected before rounding
  mpfr_t a, b, c;
  int has_a, has_b, has_c;
  long n;
  char *literal;
  // results
  mpfr_t y;
  char *digits;
  long digits_exp;
  unsigned flags;
} row_t;

static void row_init(row_t *row) {
  memset(row, 0, sizeof(*row));
  mpfr_init2(row->a, 2);
  mpfr_init2(row->b, 2);
  mpfr_init2(row->c, 2);
  mpfr_init2(row->y, 2);
}

static void row_clear(row_t *row) {
  mpfr_clear(row->a);
  mpfr_clear(row->b);
  mpfr_clear(row->c);
  mpfr_clear(row->y);
  free(row->literal);
  free(row->digits);
}

// ------------------------------------------------------------- printing ---

static void print_hex(FILE *out, const mpfr_t value) {
  if (mpfr_nan_p(value)) {
    fputs("nan", out);
    return;
  }
  if (mpfr_inf_p(value)) {
    fputs(mpfr_signbit(value) ? "-inf" : "inf", out);
    return;
  }
  if (mpfr_zero_p(value)) {
    fputs(mpfr_signbit(value) ? "-0x0p0" : "0x0p0", out);
    return;
  }
  mpz_t coefficient;
  mpz_init(coefficient);
  mpfr_exp_t exponent = mpfr_get_z_2exp(coefficient, value);
  if (mpz_sgn(coefficient) < 0) {
    fputs("-0x", out);
    mpz_neg(coefficient, coefficient);
  } else {
    fputs("0x", out);
  }
  // Strip trailing zero bits: rows stay short and the operand is canonical.
  mp_bitcnt_t zeros = mpz_scan1(coefficient, 0);
  mpz_tdiv_q_2exp(coefficient, coefficient, zeros);
  exponent += (mpfr_exp_t)zeros;
  mpz_out_str(out, 16, coefficient);
  fprintf(out, "p%ld", (long)exponent);
  mpz_clear(coefficient);
}

static void print_flags(FILE *out, unsigned flags) {
  if (flags == 0) {
    fputc('-', out);
    return;
  }
  if (flags & F_INEXACT) fputc('x', out);
  if (flags & F_OVERFLOW) fputc('o', out);
  if (flags & F_UNDERFLOW) fputc('u', out);
  if (flags & F_INVALID) fputc('v', out);
  if (flags & F_DIVZERO) fputc('z', out);
}

static void print_operand(FILE *out, int present, const mpfr_t value) {
  if (!present) {
    fputc('-', out);
  } else {
    print_hex(out, value);
  }
}

static void print_row(FILE *out, const row_t *row) {
  fprintf(out, "%s %s %s %ld ", row->id, row->op->name,
          rounding_names[row->rounding], row->precision);
  if (row->bounded) {
    fprintf(out, "%ld %ld %c ", row->emin, row->emax, row->before ? 'b' : 'a');
  } else {
    fputs("- - - ", out);
  }
  if (row->op->kind == K_STRTOFR) {
    fputs(row->literal, out);
  } else {
    print_operand(out, row->has_a, row->a);
  }
  fputc(' ', out);
  print_operand(out, row->has_b, row->b);
  fputc(' ', out);
  print_operand(out, row->has_c, row->c);
  fprintf(out, " %ld ", row->n);
  if (row->op->kind == K_GETSTR) {
    fprintf(out, "%se%ld", row->digits, row->digits_exp);
  } else if (row->op->kind == K_SHORTEST) {
    fprintf(out, "%ld", row->digits_exp);
  } else {
    print_hex(out, row->y);
  }
  fputc(' ', out);
  print_flags(out, row->flags);
  fputc('\n', out);
}

// ---------------------------------------------------------- computation ---

// mpfr_compound_si of MPFR 4.2.2 (the Homebrew build) is not correctly rounded
// for a negative n in the directed modes, nor at the ends of the exponent
// range: 15 of 1,000,000 rows of the family elem3 and 2,017 of 718,824 range
// boundary rows are wrong (the neighbour on the wrong side, a missing overflow
// flag, a flushed zero where the smallest subnormal belongs). For example
// (1 + 7/64)^-2 = 4096/5041 = 0.81254 rounded toward negative infinity at 4 bits
// is 13/16, MPFR gives 3/4. (1 + x)^n is an exact rational, so wherever its
// numerator and denominator are of a manageable size it is formed with GMP and
// rounded by mpfr_set_q, which is correctly rounded and honours the exponent
// range of the row; mpfr_compound_si is used only for the remaining rows. The
// exact value agrees with every row that mpfr_compound_si gets right, and the
// disagreeing rows are proven by exact rational arithmetic (see
// docs/verification.md).
static int compound_exact(mpfr_t y, const mpfr_t x, long n, mpfr_rnd_t rnd,
                          int *done) {
  *done = 0;
  if (n == 0 || !mpfr_regular_p(x)) return 0;
  mpz_t m, num, den, power_num, power_den;
  mpz_inits(m, num, den, power_num, power_den, NULL);
  mpfr_exp_t e = mpfr_get_z_2exp(m, x);
  mp_bitcnt_t trailing = mpz_scan1(m, 0);
  mpz_tdiv_q_2exp(m, m, trailing);  // the operand is read at 512 bits
  e += (mpfr_exp_t)trailing;
  int ternary = 0;
  if (e > -3000000L && e < 3000000L) {
    if (e < 0) {
      mpz_set_ui(den, 1);
      mpz_mul_2exp(den, den, (mp_bitcnt_t)-e);
      mpz_add(num, m, den);
    } else {
      mpz_mul_2exp(num, m, (mp_bitcnt_t)e);
      mpz_add_ui(num, num, 1);
      mpz_set_ui(den, 1);
    }
    unsigned long count = (unsigned long)labs(n);
    if (mpz_sgn(num) > 0 &&
        ((unsigned long)mpz_sizeinbase(num, 2) +
         (unsigned long)mpz_sizeinbase(den, 2)) * count <= 3000000UL) {
      mpz_pow_ui(power_num, num, count);
      mpz_pow_ui(power_den, den, count);
      mpq_t q;
      mpq_init(q);
      if (n > 0) {
        mpz_set(mpq_numref(q), power_num);
        mpz_set(mpq_denref(q), power_den);
      } else {
        mpz_set(mpq_numref(q), power_den);
        mpz_set(mpq_denref(q), power_num);
      }
      mpq_canonicalize(q);
      ternary = mpfr_set_q(y, q, rnd);
      *done = 1;
      mpq_clear(q);
    }
  }
  mpz_clears(m, num, den, power_num, power_den, NULL);
  return ternary;
}

static int apply_op(const row_t *row, mpfr_t y, mpfr_rnd_t rnd) {
  const char *name = row->op->name;
  const mpfr_t *a = &row->a;
  const mpfr_t *b = &row->b;
  const mpfr_t *c = &row->c;
  if (!strcmp(name, "add")) return mpfr_add(y, *a, *b, rnd);
  if (!strcmp(name, "sub")) return mpfr_sub(y, *a, *b, rnd);
  if (!strcmp(name, "mul")) return mpfr_mul(y, *a, *b, rnd);
  if (!strcmp(name, "div")) return mpfr_div(y, *a, *b, rnd);
  if (!strcmp(name, "sqrt")) return mpfr_sqrt(y, *a, rnd);
  if (!strcmp(name, "fma")) return mpfr_fma(y, *a, *b, *c, rnd);
  if (!strcmp(name, "strtofr")) {
    char *end = NULL;
    int ternary = mpfr_strtofr(y, row->literal, &end, 10, rnd);
    if (end == NULL || *end != '\0') {
      fprintf(stderr, "strtofr did not consume %s\n", row->literal);
      exit(2);
    }
    return ternary;
  }
  if (!strcmp(name, "exp")) return mpfr_exp(y, *a, rnd);
  if (!strcmp(name, "exp2")) return mpfr_exp2(y, *a, rnd);
  if (!strcmp(name, "exp10")) return mpfr_exp10(y, *a, rnd);
  if (!strcmp(name, "expm1")) return mpfr_expm1(y, *a, rnd);
  if (!strcmp(name, "ln")) return mpfr_log(y, *a, rnd);
  if (!strcmp(name, "log2")) return mpfr_log2(y, *a, rnd);
  if (!strcmp(name, "log10")) return mpfr_log10(y, *a, rnd);
  if (!strcmp(name, "log1p")) return mpfr_log1p(y, *a, rnd);
  if (!strcmp(name, "exp2m1")) return mpfr_exp2m1(y, *a, rnd);
  if (!strcmp(name, "exp10m1")) return mpfr_exp10m1(y, *a, rnd);
  if (!strcmp(name, "log2p1")) return mpfr_log2p1(y, *a, rnd);
  if (!strcmp(name, "log10p1")) return mpfr_log10p1(y, *a, rnd);
  if (!strcmp(name, "rsqrt")) return mpfr_rec_sqrt(y, *a, rnd);
  if (!strcmp(name, "compound")) {
    int done;
    int ternary = compound_exact(y, *a, row->n, rnd, &done);
    if (done) return ternary;
    return mpfr_compound_si(y, *a, row->n, rnd);
  }
  if (!strcmp(name, "powr")) return mpfr_powr(y, *a, *b, rnd);
  if (!strcmp(name, "rootn")) return mpfr_rootn_si(y, *a, row->n, rnd);
  if (!strcmp(name, "pown")) return mpfr_pow_si(y, *a, row->n, rnd);
  if (!strcmp(name, "pow")) return mpfr_pow(y, *a, *b, rnd);
  if (!strcmp(name, "hypot")) return mpfr_hypot(y, *a, *b, rnd);
  if (!strcmp(name, "sin")) return mpfr_sin(y, *a, rnd);
  if (!strcmp(name, "cos")) return mpfr_cos(y, *a, rnd);
  if (!strcmp(name, "tan")) return mpfr_tan(y, *a, rnd);
  if (!strcmp(name, "sinpi")) return mpfr_sinpi(y, *a, rnd);
  if (!strcmp(name, "cospi")) return mpfr_cospi(y, *a, rnd);
  if (!strcmp(name, "tanpi")) return mpfr_tanpi(y, *a, rnd);
  if (!strcmp(name, "asin")) return mpfr_asin(y, *a, rnd);
  if (!strcmp(name, "acos")) return mpfr_acos(y, *a, rnd);
  if (!strcmp(name, "atan")) return mpfr_atan(y, *a, rnd);
  if (!strcmp(name, "atan2")) return mpfr_atan2(y, *a, *b, rnd);
  if (!strcmp(name, "asinpi")) return mpfr_asinpi(y, *a, rnd);
  if (!strcmp(name, "acospi")) return mpfr_acospi(y, *a, rnd);
  if (!strcmp(name, "atanpi")) return mpfr_atanpi(y, *a, rnd);
  if (!strcmp(name, "atan2pi")) return mpfr_atan2pi(y, *a, *b, rnd);
  if (!strcmp(name, "sinh")) return mpfr_sinh(y, *a, rnd);
  if (!strcmp(name, "cosh")) return mpfr_cosh(y, *a, rnd);
  if (!strcmp(name, "tanh")) return mpfr_tanh(y, *a, rnd);
  if (!strcmp(name, "asinh")) return mpfr_asinh(y, *a, rnd);
  if (!strcmp(name, "acosh")) return mpfr_acosh(y, *a, rnd);
  if (!strcmp(name, "atanh")) return mpfr_atanh(y, *a, rnd);
  fprintf(stderr, "unsupported operation %s\n", name);
  exit(2);
}

static int apply_rounded(const row_t *row, mpfr_t y, int rounding) {
  if (rounding == R_NA) {
    mpfr_round_nearest_away_begin(y);
    int ternary = apply_op(row, y, MPFR_RNDN);
    return mpfr_round_nearest_away_end(y, ternary);
  }
  return apply_op(row, y, rounding_modes[rounding]);
}

static int any_input_nan(const row_t *row) {
  return (row->has_a && mpfr_nan_p(row->a)) ||
         (row->has_b && mpfr_nan_p(row->b)) ||
         (row->has_c && mpfr_nan_p(row->c));
}

// Computes row->y and row->flags for K_ARITH, K_ELEM and K_STRTOFR rows.
// Returns 0 (a nearest-away result in the subnormal range is rounded on the
// subnormal grid by round_nearest_away_subnormal; no row changes its rounding).
static void clip_operand(mpfr_t x, long low, long high) {
  if (!mpfr_regular_p(x)) return;
  long leading = (long)mpfr_get_exp(x) - 1;
  if (leading > high) {
    mpfr_set_exp(x, (mpfr_exp_t)(high + 1));
  } else if (leading < low) {
    mpfr_set_exp(x, (mpfr_exp_t)(low + 1));
  }
}

// Operands must lie in the exponent range the format can hold: leading bit
// between the smallest subnormal and the largest finite binade.
static void clip_operands(row_t *row, long emin, long emax) {
  long low = emin - row->precision + 1;
  if (row->has_a && row->op->kind != K_STRTOFR) clip_operand(row->a, low, emax);
  if (row->has_b) clip_operand(row->b, low, emax);
  if (row->has_c) clip_operand(row->c, low, emax);
}

// Nearest-away rounding of a result whose binade lies below the smallest normal
// one. mpfr_subnormalize does not support round-to-nearest-away (the mode is an
// emulation by mpfr_round_nearest_away_begin/end, not a rounding mode of MPFR),
// so the value is rounded once, at the number of bits the subnormal grid has in
// the binade of the exact result: with leading exponent E below emin the grid of
// the format has the weight 2^(emin - p + 1) of its last place, so the result has
// q = E - (emin - p + 1) + 1 significant bits. E is that of the exact result,
// found by the truncated (round toward zero) result at precision p, which keeps
// the binade of the exact value; the MPFR exponent range is lowered by one more
// binade so that the truncation still sees the binade just below the smallest
// subnormal. Below the smallest subnormal the result is zero, or the smallest
// subnormal when the exact result is at least half of it (a tie rounds away from
// zero). Returns the ternary value and leaves the result in row->y.
static int round_nearest_away_subnormal(row_t *row, long emin) {
  long grid = emin - row->precision + 1; // exponent of the last place of a subnormal
  mpfr_exp_t range_min = mpfr_get_emin();
  if (mpfr_set_emin(grid)) {
    fprintf(stderr, "exponent range out of MPFR bounds: %ld\n", grid);
    exit(2);
  }
  mpfr_t truncated;
  mpfr_init2(truncated, row->precision);
  apply_op(row, truncated, MPFR_RNDZ);
  int negative = mpfr_signbit(truncated) != 0;
  int ternary;
  if (mpfr_zero_p(truncated)) {
    // below 2^(grid - 1): rounds to zero
    mpfr_set_zero(row->y, negative ? -1 : 1);
    ternary = negative ? 1 : -1;
  } else {
    long leading = (long)mpfr_get_exp(truncated) - 1;
    if (leading < grid) {
      // in [2^(grid - 1), 2^grid): rounds up in magnitude to the smallest subnormal
      mpfr_set_ui_2exp(row->y, 1, (mpfr_exp_t)grid, MPFR_RNDN);
      if (negative) mpfr_neg(row->y, row->y, MPFR_RNDN);
      ternary = negative ? -1 : 1;
    } else {
      long bits = leading - grid + 1; // 1 .. p - 1
      mpfr_t grid_value;
      mpfr_init2(grid_value, bits);
      ternary = apply_rounded(row, grid_value, R_NA);
      if (mpfr_set(row->y, grid_value, MPFR_RNDN) != 0) {
        fprintf(stderr, "a subnormal result does not fit the precision\n");
        exit(2);
      }
      mpfr_clear(grid_value);
    }
  }
  mpfr_clear(truncated);
  mpfr_set_emin(range_min);
  return ternary;
}

static int compute_real(row_t *row) {
  long emin = row->bounded ? row->emin : IMPL_EMIN;
  long emax = row->bounded ? row->emax : IMPL_EMAX;
  if (row->op->kind == K_ARITH) clip_operands(row, emin, emax);
  mpfr_exp_t saved_min = mpfr_get_emin();
  mpfr_exp_t saved_max = mpfr_get_emax();
  if (mpfr_set_emin(mpfr_get_emin_min()) || mpfr_set_emax(mpfr_get_emax_max())) {
    fprintf(stderr, "cannot reset the exponent range\n");
    exit(2);
  }
  if (mpfr_set_emin(emin - row->precision + 2) || mpfr_set_emax(emax + 1)) {
    fprintf(stderr, "exponent range out of MPFR bounds: %ld %ld %ld\n", emin,
            emax, row->precision);
    exit(2);
  }
  mpfr_set_prec(row->y, row->precision);
  mpfr_clear_flags();
  int ternary;
  unsigned overflow, flushed, invalid, divzero;
  if (row->rounding == R_NA) {
    // The nearest-away wrapper restores the flags of its caller, so the
    // exception flags come from the round-to-nearest-even evaluation (the
    // overflow threshold and the special-case invalid and division by zero
    // conditions do not depend on how a tie is broken).
    mpfr_t probe;
    mpfr_init2(probe, row->precision);
    apply_op(row, probe, MPFR_RNDN);
    overflow = mpfr_overflow_p() != 0;
    flushed = mpfr_underflow_p() != 0;
    invalid = mpfr_nanflag_p() != 0 && !any_input_nan(row);
    divzero = mpfr_divby0_p() != 0;
    mpfr_clear(probe);
    ternary = apply_rounded(row, row->y, row->rounding);
  } else {
    ternary = apply_rounded(row, row->y, row->rounding);
    overflow = mpfr_overflow_p() != 0;
    flushed = mpfr_underflow_p() != 0;
    invalid = mpfr_nanflag_p() != 0 && !any_input_nan(row);
    divzero = mpfr_divby0_p() != 0;
  }
  int regular = mpfr_regular_p(row->y);
  int tiny_after = flushed || (regular && mpfr_get_exp(row->y) <= emin);
  int subnormal_done = 0;
  if (row->rounding == R_NA && tiny_after) {
    ternary = round_nearest_away_subnormal(row, emin);
    subnormal_done = 1;
  }
  if (!subnormal_done && regular && mpfr_get_exp(row->y) <= emin) {
    mpfr_rnd_t rnd = rounding_modes[row->rounding];
    ternary = mpfr_subnormalize(row->y, ternary, rnd);
  }
  int tiny = tiny_after;
  if (row->before) {
    // Tiny before rounding: the exact result is below 2^emin in magnitude,
    // which is the case exactly when its truncation is.
    mpfr_t truncated;
    mpfr_init2(truncated, row->precision);
    mpfr_clear_flags();
    apply_rounded(row, truncated, 2);
    int flushed_z = mpfr_underflow_p() != 0;
    tiny = flushed_z ||
           (mpfr_regular_p(truncated) && mpfr_get_exp(truncated) <= emin);
    mpfr_clear(truncated);
  }
  unsigned flags = 0;
  if (ternary != 0 || overflow) flags |= F_INEXACT;
  if (overflow) flags |= F_OVERFLOW;
  if (tiny && ternary != 0) flags |= F_UNDERFLOW;
  if (invalid) flags |= F_INVALID;
  if (divzero) flags |= F_DIVZERO;
  row->flags = flags;
  mpfr_set_emin(saved_min);
  mpfr_set_emax(saved_max);
  return 0;
}

// Set when MPFR's own answer fails an exact check (see check_sqrt).
static int oracle_defect = 0;

// mpfr_sqrt of MPFR 4.2.2 (the Homebrew build) returns, for some operands whose
// precision is close to the output precision, a result that is not the
// correctly rounded root or a zero ternary value for an inexact root. The root
// is checked with exact arithmetic (y*y against the operand) and such rows are
// not emitted: the oracle must be trustworthy for a row to count.
static void check_sqrt(row_t *row) {
  if (strcmp(row->op->name, "sqrt") != 0 || !mpfr_regular_p(row->y) ||
      !mpfr_regular_p(row->a) || mpfr_sgn(row->a) < 0 ||
      (row->flags & (F_OVERFLOW | F_UNDERFLOW)))
    return;
  mpfr_t square;
  mpfr_init2(square, 2 * mpfr_get_prec(row->y) + 4);
  mpfr_mul(square, row->y, row->y, MPFR_RNDN);
  int cmp = mpfr_cmp(square, row->a);
  mpfr_clear(square);
  int inexact = (row->flags & F_INEXACT) != 0;
  int bad = (cmp == 0) == inexact;
  if (row->rounding == 2 || row->rounding == 4) bad = bad || cmp > 0;
  if (row->rounding == 3 || row->rounding == 5) bad = bad || cmp < 0;
  if (bad) oracle_defect = 1;
}

// mpfr_atan2pi of MPFR 4.2.2 takes time that grows with the exponent difference
// of its operands (5 s at a ratio of 2^(2*10^7), more than 30 s from 2^(2*10^8)
// on, where mpfr_atan2 and mpfr_atanpi answer at once), so a row whose operands
// differ by more than 100,000 binades is not an oracle row: it is counted in
// `oracle-defects-skipped` and not emitted. The library's decision for the
// extreme ratios (the anchors +-1/2 and +-1) is checked against `atanpi` of an
// exact power of two and against the thresholds just inside this limit.
static int atan2pi_too_slow(const row_t *row) {
  return strcmp(row->op->name, "atan2pi") == 0 && mpfr_regular_p(row->a) &&
         mpfr_regular_p(row->b) &&
         labs((long)mpfr_get_exp(row->a) - (long)mpfr_get_exp(row->b)) > 100000;
}

static void compute_row_real(row_t *row) {
  if (atan2pi_too_slow(row)) {
    oracle_defect = 1;
    mpfr_set_nan(row->y);
    row->flags = 0;
    return;
  }
  compute_real(row);
  check_sqrt(row);
  // IEEE 754-2019 9.2.1: "rSqrt(±0) is ±∞ and signals the divideByZero
  // exception"; mpfr_rec_sqrt(-0) is +inf, so the expected value follows the
  // standard here.
  if (strcmp(row->op->name, "rsqrt") == 0 && mpfr_zero_p(row->a) &&
      mpfr_signbit(row->a)) {
    mpfr_set_inf(row->y, -1);
    row->flags = F_DIVZERO;
  }
}

// mpfr_get_str of a positive |value| and whether the digits are exact.
static int decimal_is_exact(const mpfr_t value, const char *digits,
                            mpfr_exp_t exponent) {
  mpz_t coefficient, decimal, left, right, power;
  mpz_init(coefficient);
  mpz_init(decimal);
  mpz_init(left);
  mpz_init(right);
  mpz_init(power);
  mpfr_exp_t binary = mpfr_get_z_2exp(coefficient, value);
  mpz_abs(coefficient, coefficient);
  mpz_set_str(decimal, digits, 10);
  long scale = (long)exponent - (long)strlen(digits);
  mpz_set(left, coefficient);
  mpz_set(right, decimal);
  if (binary >= 0) {
    mpz_mul_2exp(left, left, (mp_bitcnt_t)binary);
  } else {
    mpz_mul_2exp(right, right, (mp_bitcnt_t)(-binary));
  }
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

static void compute_getstr(row_t *row) {
  mpfr_exp_t exponent;
  char *text = mpfr_get_str(NULL, &exponent, 10, (size_t)row->n, row->a,
                            rounding_modes[row->rounding]);
  const char *digits = text[0] == '-' ? text + 1 : text;
  free(row->digits);
  row->digits = strdup(digits);
  row->digits_exp = (long)exponent - 1;
  row->flags = decimal_is_exact(row->a, digits, exponent) ? 0 : F_INEXACT;
  mpfr_free_str(text);
}

// The fewest significant digits n such that the n-digit decimal below or above
// the value reads back, to nearest, as exactly this value at the same
// precision (the readable interval is convex, so one of the two neighbours
// reads back whenever any n-digit decimal does).
static void compute_shortest(row_t *row) {
  mpfr_t magnitude, parsed;
  mpfr_prec_t precision = row->precision;
  mpfr_init2(magnitude, precision);
  mpfr_init2(parsed, precision);
  mpfr_set(magnitude, row->a, MPFR_RNDN);
  mpfr_abs(magnitude, magnitude, MPFR_RNDN);
  long limit = (long)((double)precision * 0.30102999566398120) + 3;
  for (long digits = 1; digits <= limit; ++digits) {
    for (int direction = 0; direction < 2; ++direction) {
      mpfr_exp_t exponent;
      char *text = mpfr_get_str(NULL, &exponent, 10, (size_t)digits, magnitude,
                                direction == 0 ? MPFR_RNDD : MPFR_RNDU);
      size_t size = strlen(text) + 64;
      char *literal = (char *)malloc(size);
      snprintf(literal, size, "0.%se%ld", text, (long)exponent);
      mpfr_free_str(text);
      mpfr_strtofr(parsed, literal, NULL, 10, MPFR_RNDN);
      free(literal);
      if (mpfr_equal_p(parsed, magnitude)) {
        row->digits_exp = digits;
        row->flags = 0;
        mpfr_clear(parsed);
        mpfr_clear(magnitude);
        return;
      }
    }
  }
  fprintf(stderr, "no shortest digit count found for %s\n", row->id);
  exit(2);
}

static void compute_row(row_t *row) {
  switch (row->op->kind) {
    case K_GETSTR:
      compute_getstr(row);
      break;
    case K_SHORTEST:
      compute_shortest(row);
      break;
    default:
      compute_row_real(row);
  }
}

// ----------------------------------------------------------- generation ---

typedef struct {
  rng_t *rng;
  row_t *row;
} gen_t;

static long pick_precision(rng_t *rng) {
  long x = rnd_range(rng, 0, 99);
  if (x < 12) return rnd_range(rng, 2, 6);
  if (x < 32) return rnd_range(rng, 7, 64);
  if (x < 42) {
    static const long formats[] = {11, 24, 53, 64, 113, 237};
    static const long deltas[] = {-1, 0, 0, 1};
    return formats[rnd_range(rng, 0, 5)] + deltas[rnd_range(rng, 0, 3)];
  }
  if (x < 82) return rnd_log(rng, 2, PREC_MAX);
  if (x < 92) return rnd_range(rng, 64, 1000);
  return rnd_range(rng, 1000, PREC_MAX);
}

static long clamp_long(long value, long low, long high) {
  if (value < low) return low;
  if (value > high) return high;
  return value;
}

// Operand width: mixed precisions relative to the output precision.
static long pick_operand_bits(rng_t *rng, long output) {
  long x = rnd_range(rng, 0, 99);
  long bits;
  if (x < 25) {
    bits = output;
  } else if (x < 35) {
    bits = output + rnd_range(rng, -3, 3);
  } else if (x < 55) {
    bits = rnd_range(rng, 2, 64);
  } else if (x < 70) {
    bits = rnd_log(rng, 2, PREC_MAX);
  } else if (x < 85) {
    bits = output + rnd_range(rng, 1, 130);
  } else if (x < 93) {
    bits = output * 2;
  } else {
    bits = rnd_range(rng, 1, 4);
  }
  return clamp_long(bits, 1, PREC_MAX);
}

// Random odd/even mantissa with exactly `bits` bits (top bit set).
static void gen_mantissa(rng_t *rng, mpz_t m, long bits, int need_odd) {
  mpz_set_ui(m, 0);
  if (bits <= 0) bits = 1;
  long style = rnd_range(rng, 0, 7);
  if (style >= 4) style = 0;
  switch (style) {
    case 1: {  // sparse: 1, a few set bits
      mpz_setbit(m, (mp_bitcnt_t)(bits - 1));
      long extras = rnd_range(rng, 0, 3);
      for (long i = 0; i < extras && bits > 1; ++i) {
        mpz_setbit(m, (mp_bitcnt_t)rnd_range(rng, 0, bits - 1));
      }
      break;
    }
    case 2: {  // all ones
      mpz_set_ui(m, 1);
      mpz_mul_2exp(m, m, (mp_bitcnt_t)bits);
      mpz_sub_ui(m, m, 1);
      break;
    }
    case 3: {  // 100...01 or 11..100..0 style runs
      mpz_setbit(m, (mp_bitcnt_t)(bits - 1));
      if (chance(rng, 1, 2)) {
        mpz_setbit(m, 0);
      } else {
        long run = rnd_range(rng, 0, bits - 1);
        for (long i = 0; i < run; ++i) mpz_setbit(m, (mp_bitcnt_t)(bits - 2 - i));
      }
      break;
    }
    default: {  // uniform random bits
      for (long i = 0; i < bits; i += 62) {
        long chunk = bits - i < 62 ? bits - i : 62;
        u64 word = rnd64(rng) & ((((u64)1) << chunk) - 1);
        mpz_t part;
        mpz_init(part);
        mpz_set_ui(part, (unsigned long)word);
        mpz_mul_2exp(part, part, (mp_bitcnt_t)i);
        mpz_ior(m, m, part);
        mpz_clear(part);
      }
      mpz_setbit(m, (mp_bitcnt_t)(bits - 1));
      if (chance(rng, 1, 5) && bits > 2) {  // trailing zeros
        long cut = rnd_range(rng, 1, bits - 1);
        mpz_tdiv_q_2exp(m, m, (mp_bitcnt_t)cut);
        mpz_mul_2exp(m, m, (mp_bitcnt_t)cut);
      }
    }
  }
  if (need_odd) mpz_setbit(m, 0);
  if (mpz_sgn(m) == 0) mpz_set_ui(m, 1);
}

// x = (-1)^neg * m * 2^lsb, exactly. The leading exponent is clamped into the
// implementation range by moving the whole value.
static void set_mz(mpfr_t x, const mpz_t m, long lsb, int neg) {
  long bits = (long)mpz_sizeinbase(m, 2);
  long leading = lsb + bits - 1;
  if (leading > IMPL_EMAX) lsb -= leading - IMPL_EMAX;
  if (leading < IMPL_EMIN) lsb += IMPL_EMIN - leading;
  mpfr_set_prec(x, bits < 2 ? 2 : bits);
  mpfr_set_z_2exp(x, m, lsb, MPFR_RNDN);
  if (neg) mpfr_neg(x, x, MPFR_RNDN);
}

static void set_special(rng_t *rng, mpfr_t x, int allow_nan) {
  long k = rnd_range(rng, 0, allow_nan ? 4 : 3);
  mpfr_set_prec(x, 2);
  switch (k) {
    case 0: mpfr_set_zero(x, 1); break;
    case 1: mpfr_set_zero(x, -1); break;
    case 2: mpfr_set_inf(x, 1); break;
    case 3: mpfr_set_inf(x, -1); break;
    default: mpfr_set_nan(x);
  }
}

static int is_special(const mpfr_t x) { return !mpfr_regular_p(x); }

// Value with `bits` significant bits and leading-bit exponent `leading`.
static void make_value(rng_t *rng, mpfr_t x, long bits, long leading, int neg,
                       int need_odd) {
  mpz_t m;
  mpz_init(m);
  gen_mantissa(rng, m, bits, need_odd);
  set_mz(x, m, leading - ((long)mpz_sizeinbase(m, 2) - 1), neg);
  mpz_clear(m);
}

// ---- context -----------------------------------------------------------

static void pick_rounding(rng_t *rng, row_t *row) {
  row->rounding = (int)rnd_range(rng, 0, 4);
}

static void pick_context(rng_t *rng, row_t *row, int allow_bounded) {
  pick_rounding(rng, row);
  row->before = chance(rng, 3, 10);
  long x = rnd_range(rng, 0, 99);
  if (!allow_bounded || x < 30) {
    row->bounded = 0;
    row->before = 0;
    row->precision = pick_precision(rng);
    return;
  }
  row->bounded = 1;
  if (x < 45) {
    static const long p[] = {11, 24, 53, 113};
    static const long e[] = {15, 127, 1023, 16383};
    long k = rnd_range(rng, 0, 3);
    row->emax = e[k];
    row->emin = 1 - e[k];
    row->precision = chance(rng, 7, 10) ? p[k] : pick_precision(rng);
  } else if (x < 70) {
    // IEEE 754-2019 3.3: emin = 1 - emax, emax >= 1
    row->emax = rnd_range(rng, 1, 40);
    row->emin = 1 - row->emax;
    row->precision = pick_precision(rng);
  } else if (x < 85) {
    row->emax = rnd_log(rng, 100, 1L << 22);
    row->emin = 1 - row->emax;
    row->precision = pick_precision(rng);
  } else {
    row->emax = rnd_range(rng, 1, 100);
    row->emin = 1 - row->emax;
    row->precision = pick_precision(rng);
  }
}

// Leading-bit exponent aimed at by the result: near the overflow threshold,
// inside the subnormal range, or moderate.
static long pick_target(rng_t *rng, const row_t *row) {
  long emin = row->bounded ? row->emin : IMPL_EMIN;
  long emax = row->bounded ? row->emax : IMPL_EMAX;
  long p = row->precision;
  long x = rnd_range(rng, 0, 99);
  if (x < 16) return emax + rnd_range(rng, -4, 3);
  if (x < 40) {
    long k = rnd_range(rng, 0, 9);
    if (k < 4) return emin + rnd_range(rng, -3, 3);
    if (k < 7) return emin - p + rnd_range(rng, -3, 3);
    return emin - rnd_range(rng, 1, p > 1 ? p : 1);
  }
  if (chance(rng, 7, 10)) {
    long v = rnd_range(rng, -60, 60);
    return clamp_long(v, emin, emax);
  }
  if (emax - emin > ((long)1 << 40)) return 0;
  return rnd_range(rng, emin, emax);
}

static long pick_gap(rng_t *rng, long p, long pa, long pb) {
  // Exponent gap between two addends: around the alignment thresholds.
  long x = rnd_range(rng, 0, 99);
  if (x < 20) return rnd_range(rng, 0, 3);
  if (x < 35) return p + rnd_range(rng, -3, 3);
  if (x < 45) return pa + rnd_range(rng, -2, 2);
  if (x < 55) return pb + rnd_range(rng, -2, 2);
  if (x < 65) return 2 * p + rnd_range(rng, -3, 3);
  if (x < 85) return rnd_range(rng, 0, 2 * p + 8);
  if (x < 95) return rnd_log(rng, 1, 100000);
  return rnd_range(rng, 100000, 2000000000L);
}

// Number of bits of the exact value of an operation when it is finite and
// short; 0 when it is not exact within the cap.
static long exact_bits(const row_t *row) {
  mpfr_t t;
  mpfr_init2(t, 60000);
  mpfr_exp_t saved_min = mpfr_get_emin(), saved_max = mpfr_get_emax();
  mpfr_set_emin(mpfr_get_emin_min());
  mpfr_set_emax(mpfr_get_emax_max());
  int ternary = apply_op(row, t, MPFR_RNDN);
  long bits = 0;
  if (ternary == 0 && mpfr_regular_p(t)) bits = (long)mpfr_min_prec(t);
  mpfr_set_emin(saved_min);
  mpfr_set_emax(saved_max);
  mpfr_clear(t);
  return bits;
}

// Adds sign*2^(lsb-extra) to x (exact), a perturbation far below the last bit
// when extra is large: the sticky bit of a near-halfway input.
static void perturb(rng_t *rng, mpfr_t x) {
  if (!mpfr_regular_p(x)) return;
  long extra = chance(rng, 1, 2) ? 0 : (chance(rng, 1, 2) ? 1 : rnd_range(rng, 2, 300));
  long lsb = (long)mpfr_get_exp(x) - (long)mpfr_min_prec(x) - extra;
  mpfr_t eps;
  mpfr_init2(eps, 2);
  mpfr_set_ui_2exp(eps, 1, lsb, MPFR_RNDN);
  if (chance(rng, 1, 2)) mpfr_neg(eps, eps, MPFR_RNDN);
  mpfr_t sum;
  mpfr_init2(sum, (mpfr_prec_t)(mpfr_min_prec(x) + extra + 8));
  mpfr_add(sum, x, eps, MPFR_RNDN);
  mpfr_set_prec(x, mpfr_get_prec(sum));
  mpfr_set(x, sum, MPFR_RNDN);
  mpfr_clear(sum);
  mpfr_clear(eps);
}

static void maybe_special_or_nan(rng_t *rng, row_t *row) {
  // A few percent of rows put a special value into one operand. NaN is never
  // combined with another operand that could add an invalid operation of its
  // own, so the only invalid flag possible is the one IEEE 754 prescribes.
  if (!chance(rng, 4, 100)) return;
  int arity = row->op->arity;
  long which = rnd_range(rng, 0, arity - 1);
  mpfr_t *target = which == 0 ? &row->a : (which == 1 ? &row->b : &row->c);
  int allow_nan = chance(rng, 1, 3);
  set_special(rng, *target, allow_nan);
  if (mpfr_nan_p(*target)) {
    for (int i = 0; i < arity; ++i) {
      mpfr_t *other = i == 0 ? &row->a : (i == 1 ? &row->b : &row->c);
      if (i != which && is_special(*other)) {
        make_value(rng, *other, 8, 0, 0, 0);
      }
    }
  }
}

// Operands whose exact result lies next to a threshold of the format: just
// below the smallest normal number (where "tiny before rounding" and "tiny
// after rounding" part ways) or just below the overflow threshold (where the
// directed and nearest modes disagree about overflow). The result is
// v = (2^j - 1) * 2^lsb with j around the precision, as an exact sum, product,
// quotient or fused result.
static void gen_boundary(rng_t *rng, row_t *row, const op_t *op) {
  long p = row->precision;
  long emin = row->bounded ? row->emin : IMPL_EMIN;
  long emax = row->bounded ? row->emax : IMPL_EMAX;
  int top = chance(rng, 1, 2);
  long j = p + rnd_range(rng, top ? -1 : 0, 4);
  if (j < 1) j = 1;
  long lsb = top ? emax + 1 - j : emin - j;
  mpz_t m;
  mpz_init(m);
  mpz_set_ui(m, 1);
  mpz_mul_2exp(m, m, (mp_bitcnt_t)j);
  mpz_sub_ui(m, m, 1);
  int neg = chance(rng, 1, 2);
  const char *name = op->name;
  mpfr_t v;
  mpfr_init2(v, 2);
  set_mz(v, m, lsb, neg);
  long shift = rnd_range(rng, -40, 40);
  if (!strcmp(name, "add") || !strcmp(name, "sub") || !strcmp(name, "fma")) {
    mpfr_t *tiny = !strcmp(name, "fma") ? &row->c : &row->b;
    mpfr_t *main_operand = &row->a;
    if (!strcmp(name, "fma")) {
      // a * b = v exactly, c is the small perturbation
      mpfr_set_prec(row->a, 2);
      mpfr_set_ui_2exp(row->a, 1, shift, MPFR_RNDN);
      mpfr_set_prec(row->b, mpfr_get_prec(v));
      mpfr_mul_2si(row->b, v, -shift, MPFR_RNDN);
    } else {
      mpfr_set_prec(*main_operand, mpfr_get_prec(v));
      mpfr_set(*main_operand, v, MPFR_RNDN);
    }
    if (chance(rng, 1, 8)) {
      mpfr_set_prec(*tiny, 2);
      mpfr_set_zero(*tiny, chance(rng, 1, 2) ? 1 : -1);
    } else {
      mpz_t t;
      mpz_init(t);
      gen_mantissa(rng, t, rnd_range(rng, 1, 8), 1);
      long below = lsb - rnd_range(rng, 0, 6) - (long)mpz_sizeinbase(t, 2);
      set_mz(*tiny, t, below, chance(rng, 1, 2));
      mpz_clear(t);
    }
  } else if (!strcmp(name, "mul")) {
    mpfr_set_prec(row->a, mpfr_get_prec(v));
    mpfr_mul_2si(row->a, v, shift, MPFR_RNDN);
    mpfr_set_prec(row->b, 2);
    mpfr_set_ui_2exp(row->b, 1, -shift, MPFR_RNDN);
  } else {  // div
    mpfr_set_prec(row->a, mpfr_get_prec(v));
    mpfr_mul_2si(row->a, v, shift, MPFR_RNDN);
    mpfr_set_prec(row->b, 2);
    mpfr_set_ui_2exp(row->b, 1, shift, MPFR_RNDN);
  }
  mpfr_clear(v);
  mpz_clear(m);
}

static void gen_arith(rng_t *rng, row_t *row, const op_t *op) {
  pick_context(rng, row, 1);
  long p = row->precision;
  long emin = row->bounded ? row->emin : IMPL_EMIN;
  long emax = row->bounded ? row->emax : IMPL_EMAX;
  long target = pick_target(rng, row);
  int subnormal_target = target < emin;
  long grid = emin - p;  // exponent of half a subnormal unit
  const char *name = op->name;
  row->has_a = 1;
  row->has_b = op->arity >= 2;
  row->has_c = op->arity >= 3;
  if (strcmp(name, "sqrt") != 0 && chance(rng, 9, 100)) {
    gen_boundary(rng, row, op);
    return;
  }
  int tie = !subnormal_target && chance(rng, 28, 100);
  int near_tie = tie && chance(rng, 45, 100);
  long pa = pick_operand_bits(rng, p);
  long pb = pick_operand_bits(rng, p);
  long pc = pick_operand_bits(rng, p);
  int neg_a = chance(rng, 1, 2), neg_b = chance(rng, 1, 2), neg_c = chance(rng, 1, 2);
  mpz_t m1, m2, m3;
  mpz_init(m1);
  mpz_init(m2);
  mpz_init(m3);

  if (!strcmp(name, "add") || !strcmp(name, "sub")) {
    long gap = pick_gap(rng, p, pa, pb);
    if (chance(rng, 1, 2)) gap = -gap;
    long la = clamp_long(target - rnd_range(rng, 0, 1), IMPL_EMIN, IMPL_EMAX);
    if (subnormal_target) {
      // Both addends are multiples of half a subnormal unit, so exact sums
      // are ties of the subnormal grid half of the time.
      long top = la - grid + 1;
      if (top < 1) top = 1;
      if (top > 20000) top = 20000;
      long ba = rnd_range(rng, 1, top);
      long bb = rnd_range(rng, 1, top);
      gen_mantissa(rng, m1, ba, chance(rng, 1, 2));
      gen_mantissa(rng, m2, bb, chance(rng, 1, 2));
      set_mz(row->a, m1, grid, neg_a);
      set_mz(row->b, m2, grid, neg_b);
    } else {
      make_value(rng, row->a, pa, la, neg_a, 0);
      make_value(rng, row->b, pb, la - gap, neg_b, 0);
      if (chance(rng, 12, 100)) {
        // cancellation: b close to -a
        mpfr_set_prec(row->b, mpfr_get_prec(row->a));
        mpfr_neg(row->b, row->a, MPFR_RNDN);
        if (chance(rng, 3, 4)) perturb(rng, row->b);
        if (!strcmp(name, "sub")) mpfr_neg(row->b, row->b, MPFR_RNDN);
      }
    }
    if (tie) {
      maybe_special_or_nan(rng, row);
      row_t *r = row;
      long n = exact_bits(r);
      if (n >= 3 && n - 1 <= PREC_MAX) {
        row->precision = n - 1;
        if (near_tie) perturb(rng, chance(rng, 1, 2) ? row->a : row->b);
      }
    }
  } else if (!strcmp(name, "mul")) {
    if (subnormal_target) {
      long total = target - grid + 1;
      if (total < 2) total = 2;
      if (total > 20000) total = 20000;
      long ba = rnd_range(rng, 1, total);
      long bb = total - ba + 1;
      gen_mantissa(rng, m1, ba, 1);
      gen_mantissa(rng, m2, bb, 1);
      long lsb_a = rnd_range(rng, -50, 50);
      set_mz(row->a, m1, lsb_a, neg_a);
      set_mz(row->b, m2, grid - lsb_a, neg_b);
    } else {
      long la = target / 2 + rnd_range(rng, -40, 40);
      if (chance(rng, 1, 5)) la = rnd_range(rng, -60, 60);
      la = clamp_long(la, IMPL_EMIN, IMPL_EMAX);
      long lb = clamp_long(target - la - rnd_range(rng, 0, 1), IMPL_EMIN, IMPL_EMAX);
      make_value(rng, row->a, pa, la, neg_a, tie);
      make_value(rng, row->b, pb, lb, neg_b, tie);
    }
    if (tie) {
      maybe_special_or_nan(rng, row);
      long n = exact_bits(row);
      if (n >= 3 && n - 1 <= PREC_MAX) {
        row->precision = n - 1;
        if (near_tie) perturb(rng, chance(rng, 1, 2) ? row->a : row->b);
      }
    }
  } else if (!strcmp(name, "div")) {
    // a = q*b makes the quotient exact (tie when p = bits(q)-1, q odd).
    long nq = subnormal_target ? clamp_long(target - grid + 1, 1, 20000) : pa;
    gen_mantissa(rng, m1, nq, 1);  // q
    gen_mantissa(rng, m2, pb, chance(rng, 1, 2));  // b
    long lb = clamp_long(rnd_range(rng, -60, 60) + (chance(rng, 1, 5) ? rnd_range(rng, -1000000, 1000000) : 0), IMPL_EMIN / 2, IMPL_EMAX / 2);
    long lq = subnormal_target ? grid : target - (long)mpz_sizeinbase(m1, 2) + 1;
    mpfr_t q;
    mpfr_init2(q, 2);
    set_mz(q, m1, lq, 0);
    set_mz(row->b, m2, lb - (long)mpz_sizeinbase(m2, 2) + 1, neg_b);
    mpfr_set_prec(row->a, (mpfr_prec_t)(mpz_sizeinbase(m1, 2) + mpz_sizeinbase(m2, 2) + 4));
    mpfr_mul(row->a, q, row->b, MPFR_RNDN);
    if (neg_a) mpfr_neg(row->a, row->a, MPFR_RNDN);
    if (!chance(rng, 1, 3) && !is_special(row->a)) {
      // not exactly divisible: any dividend
      long la = clamp_long(target + lb, IMPL_EMIN, IMPL_EMAX);
      make_value(rng, row->a, pa, la, neg_a, 0);
    } else if (near_tie || chance(rng, 1, 4)) {
      perturb(rng, row->a);
    }
    if (tie && !subnormal_target && mpz_odd_p(m1) && (long)mpz_sizeinbase(m1, 2) >= 3 &&
        (long)mpz_sizeinbase(m1, 2) - 1 <= PREC_MAX && mpfr_regular_p(row->a)) {
      row->precision = (long)mpz_sizeinbase(m1, 2) - 1;
    }
    mpfr_clear(q);
  } else if (!strcmp(name, "sqrt")) {
    // a = r*r: the root is exact, a tie for p = bits(r)-1 with r odd.
    target = clamp_long(target, IMPL_EMIN / 2 + 4, IMPL_EMAX / 2 - 4);
    long nr = subnormal_target ? clamp_long(target - grid + 1, 1, 10000) : clamp_long(pa / 2 + 1, 1, 5000);
    gen_mantissa(rng, m1, nr, 1);
    long lr = subnormal_target ? grid : target - nr + 1;
    mpfr_t r;
    mpfr_init2(r, 2);
    set_mz(r, m1, lr, 0);
    mpfr_set_prec(row->a, (mpfr_prec_t)(2 * nr + 4));
    mpfr_mul(row->a, r, r, MPFR_RNDN);
    mpfr_clear(r);
    if (chance(rng, 1, 3)) {
      long la = clamp_long(2 * target + rnd_range(rng, 0, 1), IMPL_EMIN, IMPL_EMAX);
      make_value(rng, row->a, pa, la, 0, 0);
    } else if (near_tie || chance(rng, 1, 4)) {
      perturb(rng, row->a);
    }
    if (chance(rng, 3, 100)) mpfr_neg(row->a, row->a, MPFR_RNDN);
    if (tie && !subnormal_target && mpz_odd_p(m1) && nr >= 3 && nr - 1 <= PREC_MAX) {
      row->precision = nr - 1;
    }
  } else {  // fma
    long product_lead = target - rnd_range(rng, 0, 1);
    long gap = pick_gap(rng, p, pa + pb, pc);
    if (chance(rng, 1, 2)) gap = -gap;
    if (subnormal_target) {
      long total = clamp_long(target - grid + 1, 2, 20000);
      long ba = rnd_range(rng, 1, total);
      long bb = total - ba + 1;
      gen_mantissa(rng, m1, ba, 1);
      gen_mantissa(rng, m2, bb, 1);
      long lsb_a = rnd_range(rng, -50, 50);
      set_mz(row->a, m1, lsb_a, neg_a);
      set_mz(row->b, m2, grid - lsb_a, neg_b);
      gen_mantissa(rng, m3, rnd_range(rng, 1, total), chance(rng, 1, 2));
      set_mz(row->c, m3, grid, neg_c);
    } else {
      long la = clamp_long(product_lead / 2 + rnd_range(rng, -30, 30), IMPL_EMIN, IMPL_EMAX);
      long lb = clamp_long(product_lead - la, IMPL_EMIN, IMPL_EMAX);
      make_value(rng, row->a, pa, la, neg_a, tie);
      make_value(rng, row->b, pb, lb, neg_b, tie);
      make_value(rng, row->c, pc, product_lead - gap, neg_c, 0);
      if (chance(rng, 12, 100)) {
        // cancellation: c close to -(a*b)
        mpfr_set_prec(row->c, (mpfr_prec_t)(mpfr_get_prec(row->a) + mpfr_get_prec(row->b) + 2));
        mpfr_mul(row->c, row->a, row->b, MPFR_RNDN);
        mpfr_neg(row->c, row->c, MPFR_RNDN);
        if (chance(rng, 3, 4)) perturb(rng, row->c);
      }
    }
    if (tie) {
      maybe_special_or_nan(rng, row);
      long n = exact_bits(row);
      if (n >= 3 && n - 1 <= PREC_MAX) {
        row->precision = n - 1;
        if (near_tie) perturb(rng, chance(rng, 1, 2) ? row->c : row->a);
      }
    }
  }
  if (!tie) maybe_special_or_nan(rng, row);
  mpz_clear(m1);
  mpz_clear(m2);
  mpz_clear(m3);
  (void)emax;
}

// ------------------------------------------------------------ strings ---

static void append(char **buffer, size_t *size, size_t *used, const char *text) {
  size_t length = strlen(text);
  if (*used + length + 1 > *size) {
    while (*used + length + 1 > *size) *size *= 2;
    *buffer = (char *)realloc(*buffer, *size);
  }
  memcpy(*buffer + *used, text, length + 1);
  *used += length;
}

// Decimal literal digits*10^exp10 with a random layout (point position, e/E,
// sign, leading zeros).
static char *format_literal(rng_t *rng, const char *digits, long exp10, int neg) {
  size_t size = strlen(digits) + 96, used = 0;
  char *out = (char *)malloc(size);
  out[0] = '\0';
  if (neg) append(&out, &size, &used, "-");
  else if (chance(rng, 1, 12)) append(&out, &size, &used, "+");
  size_t length = strlen(digits);
  long layout = rnd_range(rng, 0, 4);
  char buffer[64];
  if (layout == 0 || length < 2) {
    append(&out, &size, &used, digits);
  } else if (layout == 1) {
    // d.ddd with exponent compensated
    char head[2] = {digits[0], '\0'};
    append(&out, &size, &used, head);
    append(&out, &size, &used, ".");
    append(&out, &size, &used, digits + 1);
    exp10 += (long)length - 1;
  } else if (layout == 2) {
    append(&out, &size, &used, "0.");
    append(&out, &size, &used, digits);
    exp10 += (long)length;
  } else if (layout == 3) {
    append(&out, &size, &used, digits);
    append(&out, &size, &used, ".");
  } else {
    append(&out, &size, &used, ".");
    append(&out, &size, &used, digits);
    exp10 += (long)length;
  }
  if (exp10 != 0 || chance(rng, 1, 8)) {
    append(&out, &size, &used, chance(rng, 1, 2) ? "e" : "E");
    snprintf(buffer, sizeof(buffer), "%ld", exp10);
    append(&out, &size, &used, buffer);
  }
  return out;
}

static char *random_digits(rng_t *rng, long count) {
  char *digits = (char *)malloc((size_t)count + 1);
  for (long i = 0; i < count; ++i) {
    digits[i] = (char)('0' + rnd_range(rng, i == 0 ? 1 : 0, 9));
  }
  digits[count] = '\0';
  return digits;
}

static void gen_strtofr(rng_t *rng, row_t *row) {
  pick_context(rng, row, 1);
  long emin = row->bounded ? row->emin : IMPL_EMIN;
  long emax = row->bounded ? row->emax : IMPL_EMAX;
  long p = row->precision;
  long neg = chance(rng, 1, 4);
  long kind = rnd_range(rng, 0, 99);
  if (kind < 35) {
    // random literal: short, long or enormous mantissa, exponent anywhere
    long length;
    long x = rnd_range(rng, 0, 99);
    if (x < 50) length = rnd_range(rng, 1, 30);
    else if (x < 80) length = rnd_range(rng, 30, 400);
    else length = rnd_range(rng, 1, p * 31 / 100 + 25);
    if (length > 4000) length = 4000;
    char *digits = random_digits(rng, length);
    long e;
    long y = rnd_range(rng, 0, 99);
    if (y < 45) e = rnd_range(rng, -30, 30);
    else if (y < 60) e = rnd_range(rng, -3000, 3000);
    else if (y < 75) {
      // aim at the overflow threshold or the subnormal range
      long binary = chance(rng, 1, 2) ? emax : emin - rnd_range(rng, 0, p);
      e = binary * 30103L / 100000L + rnd_range(rng, -3, 3) - length;
    } else if (y < 90) e = rnd_range(rng, -400000000L, 400000000L);
    else e = rnd_range(rng, 1000000000L, 900000000000L) * (chance(rng, 1, 2) ? 1 : -1);
    row->literal = format_literal(rng, digits, e, neg);
    free(digits);
  } else {
    // halfway: m*2^k with m the midpoint of two adjacent p-bit values, a
    // neighbouring decimal one unit above or below, or with extra digits.
    mpz_t m, num;
    mpz_init(m);
    mpz_init(num);
    gen_mantissa(rng, m, p, 0);
    mpz_mul_2exp(m, m, 1);
    mpz_add_ui(m, m, 1);  // (2m+1) * 2^(k-1): exact tie at p bits
    long k = rnd_range(rng, -60, 60);
    if (chance(rng, 1, 5)) k = rnd_range(rng, -300, 300);
    if (chance(rng, 1, 6)) {
      long binary = chance(rng, 1, 2) ? emax : emin - rnd_range(rng, 0, p);
      k = binary - p;
      if (k > 3000 || k < -3000) k = clamp_long(k, -3000, 3000);
    }
    // value = m * 2^(k-1) with the leading bit of the p-bit grid at k+p-1
    long shift = k - 1;
    long scale10 = 0;
    mpz_set(num, m);
    if (shift >= 0) {
      mpz_mul_2exp(num, num, (mp_bitcnt_t)shift);
    } else {
      mpz_t five;
      mpz_init(five);
      mpz_ui_pow_ui(five, 5, (unsigned long)(-shift));
      mpz_mul(num, num, five);
      mpz_clear(five);
      scale10 = shift;
    }
    long variant = rnd_range(rng, 0, 4);
    if (variant == 1) mpz_add_ui(num, num, 1);
    else if (variant == 2) mpz_sub_ui(num, num, 1);
    else if (variant == 3) {
      mpz_mul_ui(num, num, 10);
      mpz_add_ui(num, num, 1);
      scale10 -= 1;
    } else if (variant == 4) {
      mpz_mul_ui(num, num, 10);
      mpz_sub_ui(num, num, 1);
      scale10 -= 1;
    }
    char *digits = mpz_get_str(NULL, 10, num);
    row->literal = format_literal(rng, digits, scale10, neg);
    free(digits);
    mpz_clear(m);
    mpz_clear(num);
  }
}

static void random_binary_value(rng_t *rng, mpfr_t value, long bits, long exp_limit) {
  mpz_t m;
  mpz_init(m);
  gen_mantissa(rng, m, bits, 0);
  long leading = rnd_range(rng, -exp_limit, exp_limit);
  set_mz(value, m, leading - (long)mpz_sizeinbase(m, 2) + 1, chance(rng, 1, 4));
  mpz_clear(m);
}

static void gen_getstr(rng_t *rng, row_t *row) {
  pick_rounding(rng, row);
  while (row->rounding == R_NA) pick_rounding(rng, row);
  long p = chance(rng, 1, 2) ? rnd_range(rng, 2, 120) : rnd_log(rng, 2, 2000);
  row->precision = p;
  long limit = chance(rng, 85, 100) ? 300 : (chance(rng, 4, 5) ? 20000 : 100000);
  random_binary_value(rng, row->a, p, limit);
  row->has_a = 1;
  long x = rnd_range(rng, 0, 99);
  long digits;
  long roundtrip = p * 30103L / 100000L + 2;
  if (x < 25) digits = rnd_range(rng, 1, 4);
  else if (x < 50) digits = rnd_range(rng, 1, 40);
  else if (x < 70) digits = roundtrip + rnd_range(rng, -2, 2);
  else if (x < 90) digits = rnd_range(rng, 1, roundtrip * 2 + 2);
  else digits = rnd_range(rng, 1, 1200);
  if (digits < 1) digits = 1;
  row->n = digits;
  if (chance(rng, 1, 5) && p > 2) {
    // exact ties of the digit count: x = d.dd5 * 10^k exactly in binary only
    // for small k, so pick a value m*2^-j and print one digit fewer than it
    // has (the dropped part is exactly 5000...)
    long j = rnd_range(rng, 1, 12);
    mpz_t m;
    mpz_init(m);
    mpz_set_ui(m, (unsigned long)rnd_range(rng, 1, 100000));
    mpz_mul_ui(m, m, 2);
    mpz_add_ui(m, m, 1);  // odd
    set_mz(row->a, m, -j, chance(rng, 1, 4));
    mpz_clear(m);
    row->precision = clamp_long((long)mpfr_get_prec(row->a), 2, PREC_MAX);
    row->n = rnd_range(rng, 1, 6);
  }
}

static void gen_shortest(rng_t *rng, row_t *row) {
  long p = chance(rng, 1, 2) ? rnd_range(rng, 2, 64) : rnd_log(rng, 2, 300);
  row->precision = p;
  random_binary_value(rng, row->a, p, chance(rng, 9, 10) ? 300 : 20000);
  row->has_a = 1;
}

// ----------------------------------------------------------- elementary ---

static void make_dyadic(rng_t *rng, mpfr_t x, long bits, long leading, int neg) {
  make_value(rng, x, bits, leading, neg, 0);
}

static void gen_elem(rng_t *rng, row_t *row, const op_t *op) {
  pick_rounding(rng, row);
  row->bounded = 0;
  row->before = 0;
  long x = rnd_range(rng, 0, 99);
  if (x < 15) row->precision = rnd_range(rng, 2, 12);
  else if (x < 45) row->precision = rnd_range(rng, 12, 70);
  else if (x < 55) {
    static const long formats[] = {11, 24, 53, 64, 113};
    row->precision = formats[rnd_range(rng, 0, 4)];
  } else if (x < 90) row->precision = rnd_log(rng, 2, 400);
  else row->precision = rnd_range(rng, 100, 700);
  long p = row->precision;
  const char *name = op->name;
  row->has_a = 1;
  row->has_b = op->arity >= 2;
  long pa = chance(rng, 1, 3) ? rnd_range(rng, 1, 8) : (chance(rng, 1, 2) ? p : rnd_range(rng, 1, 130));
  long pb = rnd_range(rng, 1, 130);
  int neg = chance(rng, 1, 2);
  long lead;
  long y = rnd_range(rng, 0, 99);
  // exponent of an "ordinary" argument
  if (y < 55) lead = rnd_range(rng, -4, 6);
  else if (y < 75) lead = rnd_range(rng, -40, 12);
  else if (y < 90) lead = rnd_range(rng, -200, 200);
  else lead = rnd_range(rng, -3000, 40);
  row->n = 0;
  if (!strcmp(name, "ln") || !strcmp(name, "log2") || !strcmp(name, "log10")) {
    if (chance(rng, 1, 5)) {
      // near 1: 1 +- tiny
      long e = rnd_range(rng, 2, 60);
      mpfr_set_prec(row->a, (mpfr_prec_t)(pa + e + 4));
      mpfr_set_ui_2exp(row->a, 1, -e, MPFR_RNDN);
      if (chance(rng, 1, 2)) {
        mpfr_neg(row->a, row->a, MPFR_RNDN);
      }
      mpfr_add_ui(row->a, row->a, 1, MPFR_RNDN);
    } else {
      make_dyadic(rng, row->a, pa, lead, 0);
    }
  } else if (!strcmp(name, "log1p") || !strcmp(name, "log2p1") ||
             !strcmp(name, "log10p1")) {
    if (chance(rng, 1, 6)) {
      // close to -1
      long e = rnd_range(rng, 1, 40);
      mpfr_set_prec(row->a, (mpfr_prec_t)(pa + e + 4));
      mpfr_set_ui_2exp(row->a, 1, -e, MPFR_RNDN);
      mpfr_sub_ui(row->a, row->a, 1, MPFR_RNDN);
    } else {
      make_dyadic(rng, row->a, pa, lead, neg && lead >= 0 ? 0 : neg);
      if (mpfr_cmp_si(row->a, -1) <= 0) make_dyadic(rng, row->a, pa, -2, 1);
    }
  } else if (!strcmp(name, "acosh")) {
    make_dyadic(rng, row->a, pa, rnd_range(rng, 0, 20), 0);
    if (chance(rng, 1, 4)) {
      // 1 + tiny
      long e = rnd_range(rng, 1, 40);
      mpfr_set_prec(row->a, (mpfr_prec_t)(pa + e + 4));
      mpfr_set_ui_2exp(row->a, 1, -e, MPFR_RNDN);
      mpfr_add_ui(row->a, row->a, 1, MPFR_RNDN);
    }
  } else if (!strcmp(name, "asin") || !strcmp(name, "acos") || !strcmp(name, "atanh") ||
             !strcmp(name, "asinpi") || !strcmp(name, "acospi")) {
    long e = rnd_range(rng, -30, -1);
    // acosPi clusters at 1/2 for a tiny |x| and asinPi/acosPi flush for the
    // smallest ones: reach |x| below 2^-(p + 4) as well
    if ((!strcmp(name, "asinpi") || !strcmp(name, "acospi")) && chance(rng, 1, 5))
      e = -(p + rnd_range(rng, 2, 40));
    make_dyadic(rng, row->a, pa, e, neg);
    if (chance(rng, 1, 8)) {  // near +-1
      long k = rnd_range(rng, 2, 40);
      mpfr_set_prec(row->a, (mpfr_prec_t)(pa + k + 4));
      mpfr_set_ui_2exp(row->a, 1, -k, MPFR_RNDN);
      mpfr_ui_sub(row->a, 1, row->a, MPFR_RNDN);
      if (neg) mpfr_neg(row->a, row->a, MPFR_RNDN);
    }
  } else if (!strcmp(name, "sinpi") || !strcmp(name, "cospi") || !strcmp(name, "tanpi")) {
    make_dyadic(rng, row->a, pa, rnd_range(rng, -12, 10), neg);
  } else if (!strcmp(name, "sin") || !strcmp(name, "cos") || !strcmp(name, "tan")) {
    long l = chance(rng, 85, 100) ? rnd_range(rng, -30, 12) : rnd_range(rng, 12, 300);
    make_dyadic(rng, row->a, pa, l, neg);
  } else if (!strcmp(name, "exp") || !strcmp(name, "exp2") || !strcmp(name, "exp10") ||
             !strcmp(name, "expm1") || !strcmp(name, "exp2m1") ||
             !strcmp(name, "exp10m1") || !strcmp(name, "sinh") || !strcmp(name, "cosh") ||
             !strcmp(name, "tanh")) {
    long l = rnd_range(rng, -60, 10);
    if (chance(rng, 3, 100)) l = rnd_range(rng, 28, 32);  // overflow range
    make_dyadic(rng, row->a, pa, l, neg);
  } else if (!strcmp(name, "rsqrt")) {
    // positive operands, a few negative ones and the special values below
    make_dyadic(rng, row->a, pa, lead, chance(rng, 1, 10));
  } else if (!strcmp(name, "compound")) {
    row->n = chance(rng, 1, 6) ? -rnd_range(rng, 1, 25) : rnd_range(rng, 1, 40);
    if (chance(rng, 1, 25)) row->n = rnd_range(rng, 41, 100000);
    if (chance(rng, 1, 25)) row->n = -rnd_range(rng, 26, 100000);
    if (chance(rng, 1, 6)) {
      // close to -1
      long e = rnd_range(rng, 1, 40);
      mpfr_set_prec(row->a, (mpfr_prec_t)(pa + e + 4));
      mpfr_set_ui_2exp(row->a, 1, -e, MPFR_RNDN);
      mpfr_sub_ui(row->a, row->a, 1, MPFR_RNDN);
    } else {
      make_dyadic(rng, row->a, pa, rnd_range(rng, -30, 6), neg && chance(rng, 1, 3));
      if (mpfr_cmp_si(row->a, -1) < 0) make_dyadic(rng, row->a, pa, -2, 1);
    }
  } else if (!strcmp(name, "powr")) {
    make_dyadic(rng, row->a, pa, rnd_range(rng, -6, 6), chance(rng, 1, 12));
    make_dyadic(rng, row->b, pb, rnd_range(rng, -6, 6), neg);
  } else if (!strcmp(name, "rootn")) {
    row->n = chance(rng, 1, 8) ? -rnd_range(rng, 1, 10) : rnd_range(rng, 2, 12);
    if (chance(rng, 1, 30)) row->n = rnd_range(rng, 13, 3000);
    make_dyadic(rng, row->a, pa, lead, neg && (row->n % 2 != 0 || chance(rng, 1, 20)));
  } else if (!strcmp(name, "pown")) {
    row->n = rnd_range(rng, -25, 40);
    if (chance(rng, 1, 25)) row->n = rnd_range(rng, 41, 100000);
    make_dyadic(rng, row->a, pa, rnd_range(rng, -3, 3), neg);
  } else if (!strcmp(name, "pow")) {
    make_dyadic(rng, row->a, pa, rnd_range(rng, -6, 6), chance(rng, 1, 12));
    long e = rnd_range(rng, -6, 6);
    make_dyadic(rng, row->b, pb, e, neg);
    if (mpfr_signbit(row->a) && !mpfr_integer_p(row->b)) {
      // a negative base needs an integer exponent to stay out of NaN noise
      long k = rnd_range(rng, -40, 40);
      mpfr_set_si(row->b, k, MPFR_RNDN);
    }
  } else if (!strcmp(name, "hypot") || !strcmp(name, "atan2") || !strcmp(name, "atan2pi")) {
    long la = rnd_range(rng, -8, 8);
    make_dyadic(rng, row->a, pa, la, neg);
    // atan2Pi anchors at +-1/2 and +-1 for |y/x| beyond 2^(+-(p + 8)): reach it
    long reach = !strcmp(name, "atan2pi") ? p + 40 : p + 4;
    long lb = la + rnd_range(rng, -reach, reach);
    if (chance(rng, 1, 3)) lb = rnd_range(rng, -8, 8);
    make_dyadic(rng, row->b, pb, lb, chance(rng, 1, 2));
  } else if (!strcmp(name, "atanpi")) {
    if (chance(rng, 1, 5)) lead = p + rnd_range(rng, 2, 40);  // atanPi(x) next to +-1/2
    make_dyadic(rng, row->a, pa, lead, neg);
  } else {  // atan, asinh
    make_dyadic(rng, row->a, pa, lead, neg);
  }
  // a small share of special arguments for the unary functions
  if (op->arity == 1 && chance(rng, 3, 100)) set_special(rng, row->a, 1);
}

// ----------------------------------------------------------- generation ---

static void gen_row(rng_t *rng, row_t *row, const op_t *op) {
  row->op = op;
  switch (op->kind) {
    case K_ARITH:
      gen_arith(rng, row, op);
      break;
    case K_ELEM:
      gen_elem(rng, row, op);
      break;
    case K_STRTOFR:
      gen_strtofr(rng, row);
      break;
    case K_GETSTR:
      gen_getstr(rng, row);
      break;
    case K_SHORTEST:
      gen_shortest(rng, row);
      break;
  }
}

static const op_t *find_op(const char *name) {
  for (size_t i = 0; i < OP_COUNT; ++i) {
    if (!strcmp(operations[i].name, name)) return &operations[i];
  }
  return NULL;
}

// A family is an operation name, "elem" (every elementary function, picked by
// the stream), or "arith" (the six arithmetic operations).
static const op_t *pick_family_op(const char *family, rng_t *rng) {
  if (!strcmp(family, "elem")) {
    return &operations[FIRST_ELEM + rnd_range(rng, 0, (long)LEGACY_OP_COUNT - FIRST_ELEM - 1)];
  }
  if (!strcmp(family, "elem2")) {
    return &operations[LEGACY_OP_COUNT + rnd_range(rng, 0, (long)ELEM2_END - LEGACY_OP_COUNT - 1)];
  }
  if (!strcmp(family, "elem3")) {
    return &operations[ELEM2_END + rnd_range(rng, 0, (long)ELEM3_END - ELEM2_END - 1)];
  }
  if (!strcmp(family, "elem4")) {
    return &operations[ELEM3_END + rnd_range(rng, 0, (long)OP_COUNT - ELEM3_END - 1)];
  }
  if (!strcmp(family, "arith")) return &operations[rnd_range(rng, 0, 5)];
  return find_op(family);
}

static void generate(const char *family, u64 seed, long start, long count) {
  printf("# mpfr-random-v1 mpfr=%s gmp=%s family=%s seed=%llu start=%ld count=%ld\n",
         mpfr_get_version(), gmp_version, family, (unsigned long long)seed, start, count);
  puts("# id op rounding precision emin emax tininess a b c n expected flags");
  u64 family_hash = fnv1a(family);
  mpfr_set_emin(mpfr_get_emin_min());
  mpfr_set_emax(mpfr_get_emax_max());
  long skipped = 0;
  for (long index = start; index < start + count; ++index) {
    // A row whose oracle answer fails the exact check is drawn again from the
    // next stream of the same case; the id stays the same.
    for (int attempt = 0; attempt < 16; ++attempt) {
      rng_t rng;
      rng_seed(&rng, seed, family_hash, (u64)index + ((u64)attempt << 40));
      const op_t *op = pick_family_op(family, &rng);
      if (op == NULL) {
        fprintf(stderr, "unknown family %s\n", family);
        exit(2);
      }
      row_t row;
      row_init(&row);
      snprintf(row.id, sizeof(row.id), "%llu.%s.%ld", (unsigned long long)seed, family, index);
      gen_row(&rng, &row, op);
      if (row.precision < 2) row.precision = 2;
      oracle_defect = 0;
      compute_row(&row);
      if (oracle_defect && attempt < 15) {
        ++skipped;
        row_clear(&row);
        continue;
      }
      print_row(stdout, &row);
      row_clear(&row);
      break;
    }
  }
  printf("# oracle-defects-skipped %ld\n", skipped);
}

// ----------------------------------------------------------------- eval ---

static int tokenize(char *line, char **tokens, int max) {
  int count = 0;
  char *save = NULL;
  for (char *token = strtok_r(line, " \t\r\n", &save); token && count < max;
       token = strtok_r(NULL, " \t\r\n", &save)) {
    tokens[count++] = token;
  }
  return count;
}

static void parse_operand(mpfr_t x, int *present, const char *text) {
  if (!strcmp(text, "-")) {
    *present = 0;
    return;
  }
  *present = 1;
  if (!strcmp(text, "nan")) {
    mpfr_set_prec(x, 2);
    mpfr_set_nan(x);
    return;
  }
  if (!strcmp(text, "inf") || !strcmp(text, "-inf")) {
    mpfr_set_prec(x, 2);
    mpfr_set_inf(x, text[0] == '-' ? -1 : 1);
    return;
  }
  mpfr_set_prec(x, (mpfr_prec_t)(strlen(text) * 4 + 64));
  if (mpfr_set_str(x, text, 16, MPFR_RNDN) != 0) {
    fprintf(stderr, "cannot read operand %s\n", text);
    exit(2);
  }
}

static void eval_rows(void) {
  long skipped = 0;
  char *line = NULL;
  size_t capacity = 0;
  mpfr_set_emin(mpfr_get_emin_min());
  mpfr_set_emax(mpfr_get_emax_max());
  while (getline(&line, &capacity, stdin) > 0) {
    if (line[0] == '#' || line[0] == '\n') continue;
    char *copy = strdup(line);
    char *tokens[16];
    int count = tokenize(copy, tokens, 16);
    if (count != 13) {
      fprintf(stderr, "eval rows need 13 fields, got %d\n", count);
      exit(2);
    }
    row_t row;
    row_init(&row);
    snprintf(row.id, sizeof(row.id), "%s", tokens[0]);
    row.op = find_op(tokens[1]);
    if (row.op == NULL) {
      fprintf(stderr, "unknown operation %s\n", tokens[1]);
      exit(2);
    }
    row.rounding = -1;
    for (int i = 0; i < 5; ++i) {
      if (!strcmp(rounding_names[i], tokens[2])) row.rounding = i;
    }
    if (row.rounding < 0) {
      fprintf(stderr, "unknown rounding %s\n", tokens[2]);
      exit(2);
    }
    row.precision = atol(tokens[3]);
    if (strcmp(tokens[4], "-")) {
      row.bounded = 1;
      row.emin = atol(tokens[4]);
      row.emax = atol(tokens[5]);
      row.before = tokens[6][0] == 'b';
    }
    if (row.op->kind == K_STRTOFR) {
      row.literal = strdup(tokens[7]);
      row.has_a = 0;
    } else {
      parse_operand(row.a, &row.has_a, tokens[7]);
    }
    parse_operand(row.b, &row.has_b, tokens[8]);
    parse_operand(row.c, &row.has_c, tokens[9]);
    row.n = atol(tokens[10]);
    oracle_defect = 0;
    compute_row(&row);
    if (oracle_defect) {
      ++skipped;
    } else {
      print_row(stdout, &row);
    }
    row_clear(&row);
    free(copy);
  }
  free(line);
  if (skipped) fprintf(stderr, "# oracle-defects-skipped %ld\n", skipped);
}

int main(int argc, char **argv) {
  if (argc == 2 && !strcmp(argv[1], "eval")) {
    eval_rows();
    return 0;
  }
  if (argc == 2 && !strcmp(argv[1], "families")) {
    puts("arith elem");
    for (size_t i = 0; i < OP_COUNT; ++i) puts(operations[i].name);
    return 0;
  }
  if (argc != 5) {
    fprintf(stderr, "usage: %s <family> <seed> <start> <count> | eval | families\n", argv[0]);
    return 2;
  }
  char *end = NULL;
  u64 seed = (u64)strtoull(argv[2], &end, 10);
  long start = strtol(argv[3], &end, 10);
  long count = strtol(argv[4], &end, 10);
  if (start < 0 || count < 0) return 2;
  generate(argv[1], seed, start, count);
  return 0;
}
