/* Rows of the logarithm family at result precisions between 320 and 1152 bits,
 * in the format of mpfr-4.2.2-elementary.txt (see generate_mpfr_elementary_oracle.c),
 * from MPFR (mpfr_log, mpfr_log2, mpfr_log10, mpfr_log1p) with the arguments
 * written out. The elementary matrix has only 24, 53 and 113 bits; these rows
 * reach the working precisions on both sides of the thresholds at which `ln`
 * changes kernel (series below 768 working bits, Newton step from 768, the
 * arithmetic-geometric mean from 1152; working precision = result precision + 64)
 * with four argument classes: near 1, near a power of two, large or tiny, and a
 * random mantissa. The operand has at most as many bits as the result precision.
 *
 * Usage: generate_mpfr_ln_wide_oracle [cases-per-cell] [seed] */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <gmp.h>
#include <mpfr.h>

static const char *operations[] = {"ln", "log2", "log10", "log1p"};
static const mpfr_prec_t precisions[] = {
    320, 384, 448, 512, 576, 640, 688, 700, 704, 720,
    768, 832, 896, 960, 1024, 1072, 1088, 1104, 1152,
};
static const mpfr_rnd_t roundings[] = {
    MPFR_RNDN, MPFR_RNDN, MPFR_RNDZ, MPFR_RNDU, MPFR_RNDD,
};
static const char *rounding_names[] = {"n", "na", "z", "u", "d"};

static uint64_t next_random(uint64_t *state) {
  *state = *state * UINT64_C(6364136223846793005) +
           UINT64_C(1442695040888963407);
  return *state;
}

/* A random mantissa in [1, 2) with `bits` bits: the leading bit set, the rest
 * from the generator (32 bits at a time from the high half of the state). */
static void random_unit(mpfr_t value, long bits, uint64_t *state) {
  mpz_t m;
  mpz_init(m);
  mpz_set_ui(m, 1);
  for (long done = 1; done < bits;) {
    long take = bits - done < 32 ? bits - done : 32;
    mpz_mul_2exp(m, m, take);
    mpz_add_ui(m, m, (unsigned long)((next_random(state) >> 32) &
                                    ((UINT64_C(1) << take) - 1)));
    done += take;
  }
  mpfr_set_z_2exp(value, m, -(bits - 1), MPFR_RNDN);
  mpz_clear(m);
}

static void make_argument(int op, int klass, mpfr_prec_t precision,
                          mpfr_t out, uint64_t *state) {
  mpfr_t unit;
  mpfr_init2(unit, precision + 8);
  random_unit(unit, precision, state);
  mpfr_set_prec(out, precision);
  long k = 3 + (long)(next_random(state) % 78);  /* 3 .. 80 */
  long e = (long)(next_random(state) % 41) - 20; /* -20 .. 20 */
  int negative = (int)((next_random(state) >> 40) & 1);
  long big = 300 + (long)(next_random(state) % 1701); /* 300 .. 2000 */
  mpfr_t t;
  mpfr_init2(t, precision + 200);
  switch (klass) {
    case 0: /* near 1: 1 +- 2^-k u */
      mpfr_mul_2si(t, unit, -k, MPFR_RNDN);
      if (negative) mpfr_ui_sub(t, 1, t, MPFR_RNDN);
      else mpfr_add_ui(t, t, 1, MPFR_RNDN);
      break;
    case 1: /* near a power of two: 2^e (1 +- 2^-k u) */
      mpfr_mul_2si(t, unit, -k, MPFR_RNDN);
      if (negative) mpfr_ui_sub(t, 1, t, MPFR_RNDN);
      else mpfr_add_ui(t, t, 1, MPFR_RNDN);
      mpfr_mul_2si(t, t, e, MPFR_RNDN);
      break;
    case 2: /* large or tiny: u 2^(+-(300 .. 2000)) */
      mpfr_mul_2si(t, unit, negative ? -big : big, MPFR_RNDN);
      break;
    default: /* random mantissa, small exponent */
      mpfr_mul_2si(t, unit, e, MPFR_RNDN);
      break;
  }
  mpfr_set(out, t, MPFR_RNDN);
  /* log1p needs an argument above -1; ln, log2, log10 a positive one. */
  if (op == 3) {
    if (mpfr_cmp_si(out, -1) <= 0) mpfr_set_d(out, 0.5, MPFR_RNDN);
  } else if (mpfr_sgn(out) <= 0) {
    mpfr_set_d(out, 1.5, MPFR_RNDN);
  }
  mpfr_clear(t);
  mpfr_clear(unit);
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

static int evaluate(int op, mpfr_t output, const mpfr_t left,
                    mpfr_rnd_t rounding) {
  switch (op) {
    case 0: return mpfr_log(output, left, rounding);
    case 1: return mpfr_log2(output, left, rounding);
    case 2: return mpfr_log10(output, left, rounding);
    default: return mpfr_log1p(output, left, rounding);
  }
}

int main(int argc, char **argv) {
  long cases_per_cell = 1;
  uint64_t seed = UINT64_C(20261121);
  if (argc >= 2) cases_per_cell = strtol(argv[1], NULL, 10);
  if (argc >= 3) seed = (uint64_t)strtoull(argv[2], NULL, 10);
  if (cases_per_cell <= 0) {
    fprintf(stderr, "usage: %s [cases-per-cell] [seed]\n", argv[0]);
    return 2;
  }
  printf("# mpfr-elementary-v1 mpfr=%s cases-per-cell=%ld seed=%llu\n",
         mpfr_get_version(), cases_per_cell, (unsigned long long)seed);
  puts("# operation precision rounding left right integer expected inexact invalid division_by_zero");
  mpfr_t left, output;
  mpfr_init2(left, 2);
  mpfr_init2(output, 2);
  uint64_t state = seed;
  size_t precision_count = sizeof(precisions) / sizeof(precisions[0]);
  for (int op = 0; op < 4; ++op) {
    for (size_t pi = 0; pi < precision_count; ++pi) {
      for (int klass = 0; klass < 4; ++klass) {
        for (size_t ri = 0; ri < 5; ++ri) {
          for (long ci = 0; ci < cases_per_cell; ++ci) {
            make_argument(op, klass, precisions[pi], left, &state);
            mpfr_set_prec(output, precisions[pi]);
            mpfr_clear_flags();
            int ternary;
            if (ri == 1) {
              mpfr_round_nearest_away_begin(output);
              ternary = evaluate(op, output, left, MPFR_RNDN);
              ternary = mpfr_round_nearest_away_end(output, ternary);
            } else {
              ternary = evaluate(op, output, left, roundings[ri]);
            }
            printf("%s %ld %s ", operations[op], (long)precisions[pi],
                   rounding_names[ri]);
            print_hex(left);
            fputs(" - 0 ", stdout);
            print_hex(output);
            /* The arguments are in the domain by construction (positive for ln,
             * log2, log10; above -1 for log1p, never 0 or -1), so the invalid and
             * division-by-zero flags are 0; the MPFR macros of the nearest-away
             * mode leave the NaN flag set at these precisions, so the flags are
             * not read from them. A NaN or infinite result would be a bug here. */
            if (mpfr_nan_p(output) || mpfr_inf_p(output)) {
              fprintf(stderr, "unexpected special result\n");
              return 1;
            }
            printf(" %d 0 0\n", ternary != 0);
          }
        }
      }
    }
  }
  mpfr_clear(output);
  mpfr_clear(left);
  return 0;
}
