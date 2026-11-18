/*
 * MPFR enclosures of decimal elementary functions, for
 * tools/generate_mpfr_decimal_random.py.
 *
 * Reads one case per line on stdin, `operation a b n`, where `a` and `b` are
 * finite decimal literals (`-` when absent) and `n` is an integer, and writes
 * one line per case: `skip`, or `<lower coefficient> <lower exponent2>
 * <upper coefficient> <upper exponent2>` where lower and upper are the integers
 * m and e of m * 2^e, so that lower <= f(a, b) <= upper holds for the exact
 * decimal operands.
 *
 * Rigour: each decimal operand is bracketed by its 2048-bit RNDD and RNDU
 * values; f is evaluated at 768 bits with RNDD and RNDU on every corner of the
 * operand box; the enclosure is the minimum of the lower and the maximum of the
 * upper results, widened by one ulp (which also covers a monotonicity break
 * inside the 2^-2048-wide box). A corner whose result is NaN, infinite or
 * outside the exponent range makes the case `skip`. MPFR is an oracle, not an
 * authority: the Python side rejects every enclosure that does not round to a
 * single result.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gmp.h>
#include <mpfr.h>

#define OPERAND_PRECISION 2048
#define RESULT_PRECISION 768

static int evaluate(const char *operation, mpfr_t output, const mpfr_t left,
                    const mpfr_t right, long integer, mpfr_rnd_t rounding) {
#define UNARY(name, function) \
  if (strcmp(operation, name) == 0) return function(output, left, rounding)
  UNARY("exp", mpfr_exp);
  UNARY("exp2", mpfr_exp2);
  UNARY("exp10", mpfr_exp10);
  UNARY("expm1", mpfr_expm1);
  UNARY("ln", mpfr_log);
  UNARY("log2", mpfr_log2);
  UNARY("log10", mpfr_log10);
  UNARY("log1p", mpfr_log1p);
  UNARY("sin", mpfr_sin);
  UNARY("cos", mpfr_cos);
  UNARY("tan", mpfr_tan);
  UNARY("sinpi", mpfr_sinpi);
  UNARY("cospi", mpfr_cospi);
  UNARY("tanpi", mpfr_tanpi);
  UNARY("asin", mpfr_asin);
  UNARY("acos", mpfr_acos);
  UNARY("atan", mpfr_atan);
  UNARY("sinh", mpfr_sinh);
  UNARY("cosh", mpfr_cosh);
  UNARY("tanh", mpfr_tanh);
  UNARY("asinh", mpfr_asinh);
  UNARY("acosh", mpfr_acosh);
  UNARY("atanh", mpfr_atanh);
  UNARY("exp2m1", mpfr_exp2m1);
  UNARY("exp10m1", mpfr_exp10m1);
  UNARY("log2p1", mpfr_log2p1);
  UNARY("log10p1", mpfr_log10p1);
  UNARY("rsqrt", mpfr_rec_sqrt);
  UNARY("asinpi", mpfr_asinpi);
  UNARY("acospi", mpfr_acospi);
  UNARY("atanpi", mpfr_atanpi);
#undef UNARY
  if (strcmp(operation, "pow") == 0)
    return mpfr_pow(output, left, right, rounding);
  if (strcmp(operation, "powr") == 0)
    return mpfr_powr(output, left, right, rounding);
  if (strcmp(operation, "hypot") == 0)
    return mpfr_hypot(output, left, right, rounding);
  if (strcmp(operation, "atan2") == 0)
    return mpfr_atan2(output, left, right, rounding);
  if (strcmp(operation, "atan2pi") == 0)
    return mpfr_atan2pi(output, left, right, rounding);
  if (strcmp(operation, "rootn") == 0)
    return mpfr_rootn_ui(output, left, (unsigned long)integer, rounding);
  if (strcmp(operation, "pown") == 0)
    return mpfr_pow_si(output, left, integer, rounding);
  if (strcmp(operation, "compound") == 0)
    return mpfr_compound_si(output, left, integer, rounding);
  fprintf(stderr, "unsupported operation: %s\n", operation);
  exit(2);
}

static int usable(const mpfr_t value) {
  return !mpfr_nan_p(value) && !mpfr_inf_p(value);
}

static void print_dyadic(const mpfr_t value) {
  mpz_t mantissa;
  mpz_init(mantissa);
  if (mpfr_zero_p(value)) {
    printf("0 0");
  } else {
    mpfr_exp_t exponent = mpfr_get_z_2exp(mantissa, value);
    gmp_printf("%Zd %ld", mantissa, (long)exponent);
  }
  mpz_clear(mantissa);
}

int main(void) {
  mpfr_set_emin(mpfr_get_emin_min());
  mpfr_set_emax(mpfr_get_emax_max());
  mpfr_t operand_low[2], operand_high[2], lower, upper, candidate;
  for (int i = 0; i < 2; ++i) {
    mpfr_init2(operand_low[i], OPERAND_PRECISION);
    mpfr_init2(operand_high[i], OPERAND_PRECISION);
  }
  mpfr_init2(lower, RESULT_PRECISION);
  mpfr_init2(upper, RESULT_PRECISION);
  mpfr_init2(candidate, RESULT_PRECISION);
  char *line = NULL;
  size_t capacity = 0;
  puts("# mpfr-decimal-enclosure-v1");
  printf("# mpfr=%s result-precision=%d operand-precision=%d\n",
         mpfr_get_version(), RESULT_PRECISION, OPERAND_PRECISION);
  while (getline(&line, &capacity, stdin) >= 0) {
    char operation[32], first[4096], second[4096];
    long integer = 0;
    if (sscanf(line, "%31s %4095s %4095s %ld", operation, first, second,
               &integer) != 4) {
      puts("skip");
      continue;
    }
    int arguments = strcmp(second, "-") == 0 ? 1 : 2;
    const char *texts[2] = {first, second};
    for (int i = 0; i < arguments; ++i) {
      mpfr_set_str(operand_low[i], texts[i], 10, MPFR_RNDD);
      mpfr_set_str(operand_high[i], texts[i], 10, MPFR_RNDU);
    }
    if (arguments == 1) {
      mpfr_set_ui(operand_low[1], 0, MPFR_RNDN);
      mpfr_set_ui(operand_high[1], 0, MPFR_RNDN);
    }
    int ok = 1;
    int have = 0;
    for (int a = 0; a < 2 && ok; ++a) {
      for (int b = 0; b < (arguments == 2 ? 2 : 1) && ok; ++b) {
        const mpfr_t *left = a ? &operand_high[0] : &operand_low[0];
        const mpfr_t *right = b ? &operand_high[1] : &operand_low[1];
        evaluate(operation, candidate, *left, *right, integer, MPFR_RNDD);
        if (!usable(candidate)) {
          ok = 0;
          break;
        }
        if (!have || mpfr_less_p(candidate, lower)) mpfr_set(lower, candidate, MPFR_RNDD);
        evaluate(operation, candidate, *left, *right, integer, MPFR_RNDU);
        if (!usable(candidate)) {
          ok = 0;
          break;
        }
        if (!have || mpfr_greater_p(candidate, upper)) mpfr_set(upper, candidate, MPFR_RNDU);
        have = 1;
      }
    }
    if (!ok || !have) {
      puts("skip");
      continue;
    }
    mpfr_nextbelow(lower);
    mpfr_nextabove(upper);
    print_dyadic(lower);
    fputc(' ', stdout);
    print_dyadic(upper);
    fputc('\n', stdout);
  }
  free(line);
  return 0;
}
