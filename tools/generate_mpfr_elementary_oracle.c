#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <gmp.h>
#include <mpfr.h>

typedef struct {
  const char *name;
  int arity;
} operation_spec;

static const operation_spec operations[] = {
    {"exp", 1},    {"exp2", 1},  {"exp10", 1}, {"expm1", 1},
    {"ln", 1},     {"log2", 1},  {"log10", 1}, {"log1p", 1},
    {"sqrt", 1},   {"rootn", 1}, {"pown", 1},  {"pow", 2},
    {"hypot", 2},  {"sin", 1},   {"cos", 1},   {"tan", 1},
    {"sinpi", 1},  {"cospi", 1}, {"tanpi", 1}, {"asin", 1},
    {"acos", 1},   {"atan", 1},  {"atan2", 2}, {"sinh", 1},
    {"cosh", 1},   {"tanh", 1},  {"asinh", 1}, {"acosh", 1},
    {"atanh", 1},
};

static const mpfr_prec_t precisions[] = {24, 53, 113};
static const mpfr_rnd_t roundings[] = {
    MPFR_RNDN, MPFR_RNDN, MPFR_RNDZ, MPFR_RNDU, MPFR_RNDD, MPFR_RNDA,
};
static const char *rounding_names[] = {"n", "na", "z", "u", "d", "a"};

static uint64_t next_random(uint64_t *state) {
  *state = *state * UINT64_C(6364136223846793005) +
           UINT64_C(1442695040888963407);
  return *state;
}

static long signed_numerator(uint64_t *state, long limit) {
  uint64_t width = (uint64_t)(2 * limit + 1);
  return (long)(next_random(state) % width) - limit;
}

static long positive_numerator(uint64_t *state, long maximum) {
  return (long)(next_random(state) % (uint64_t)maximum) + 1;
}

static void set_dyadic(mpfr_t value, long numerator) {
  mpfr_set_si_2exp(value, numerator, -8, MPFR_RNDN);
}

static void make_operands(
    const char *operation,
    mpfr_t left,
    mpfr_t right,
    long *integer,
    uint64_t *state) {
  *integer = 0;
  if (strcmp(operation, "ln") == 0 || strcmp(operation, "log2") == 0 ||
      strcmp(operation, "log10") == 0 || strcmp(operation, "sqrt") == 0) {
    set_dyadic(left, positive_numerator(state, 4096));
  } else if (strcmp(operation, "log1p") == 0) {
    set_dyadic(left, signed_numerator(state, 2048));
    if (mpfr_cmp_si(left, -1) <= 0) {
      set_dyadic(left, -255 + (long)(next_random(state) % 2304));
    }
  } else if (strcmp(operation, "rootn") == 0) {
    *integer = 2 + (long)(next_random(state) % 6);
    long numerator = signed_numerator(state, 4096);
    if (*integer % 2 == 0 && numerator < 0) {
      numerator = -numerator;
    }
    if (numerator == 0) {
      numerator = 1;
    }
    set_dyadic(left, numerator);
  } else if (strcmp(operation, "pown") == 0) {
    *integer = (long)(next_random(state) % 15) - 7;
    long numerator = signed_numerator(state, 2048);
    if (numerator == 0 && *integer < 0) {
      numerator = 1;
    }
    set_dyadic(left, numerator);
  } else if (strcmp(operation, "pow") == 0) {
    set_dyadic(left, positive_numerator(state, 2048));
    set_dyadic(right, signed_numerator(state, 768));
  } else if (strcmp(operation, "hypot") == 0 ||
             strcmp(operation, "atan2") == 0) {
    long left_numerator = signed_numerator(state, 2048);
    long right_numerator = signed_numerator(state, 2048);
    if (strcmp(operation, "atan2") == 0 && left_numerator == 0 &&
        right_numerator == 0) {
      right_numerator = 1;
    }
    set_dyadic(left, left_numerator);
    set_dyadic(right, right_numerator);
  } else if (strcmp(operation, "asin") == 0 ||
             strcmp(operation, "acos") == 0) {
    set_dyadic(left, signed_numerator(state, 256));
  } else if (strcmp(operation, "atanh") == 0) {
    set_dyadic(left, signed_numerator(state, 255));
  } else if (strcmp(operation, "acosh") == 0) {
    set_dyadic(left, 256 + (long)(next_random(state) % 3841));
  } else if (strcmp(operation, "sinpi") == 0 ||
             strcmp(operation, "cospi") == 0 ||
             strcmp(operation, "tanpi") == 0) {
    long numerator = signed_numerator(state, 2048);
    if (strcmp(operation, "tanpi") == 0 && numerator % 128 == 0) {
      numerator += 1;
    }
    set_dyadic(left, numerator);
  } else {
    set_dyadic(left, signed_numerator(state, 1024));
  }
}

static int evaluate(
    const char *operation,
    mpfr_t output,
    const mpfr_t left,
    const mpfr_t right,
    long integer,
    mpfr_rnd_t rounding) {
  if (strcmp(operation, "exp") == 0) return mpfr_exp(output, left, rounding);
  if (strcmp(operation, "exp2") == 0) return mpfr_exp2(output, left, rounding);
  if (strcmp(operation, "exp10") == 0)
    return mpfr_exp10(output, left, rounding);
  if (strcmp(operation, "expm1") == 0)
    return mpfr_expm1(output, left, rounding);
  if (strcmp(operation, "ln") == 0) return mpfr_log(output, left, rounding);
  if (strcmp(operation, "log2") == 0) return mpfr_log2(output, left, rounding);
  if (strcmp(operation, "log10") == 0)
    return mpfr_log10(output, left, rounding);
  if (strcmp(operation, "log1p") == 0)
    return mpfr_log1p(output, left, rounding);
  if (strcmp(operation, "sqrt") == 0) return mpfr_sqrt(output, left, rounding);
  if (strcmp(operation, "rootn") == 0)
    return mpfr_rootn_ui(output, left, (unsigned long)integer, rounding);
  if (strcmp(operation, "pown") == 0)
    return mpfr_pow_si(output, left, integer, rounding);
  if (strcmp(operation, "pow") == 0)
    return mpfr_pow(output, left, right, rounding);
  if (strcmp(operation, "hypot") == 0)
    return mpfr_hypot(output, left, right, rounding);
  if (strcmp(operation, "sin") == 0) return mpfr_sin(output, left, rounding);
  if (strcmp(operation, "cos") == 0) return mpfr_cos(output, left, rounding);
  if (strcmp(operation, "tan") == 0) return mpfr_tan(output, left, rounding);
  if (strcmp(operation, "sinpi") == 0)
    return mpfr_sinpi(output, left, rounding);
  if (strcmp(operation, "cospi") == 0)
    return mpfr_cospi(output, left, rounding);
  if (strcmp(operation, "tanpi") == 0)
    return mpfr_tanpi(output, left, rounding);
  if (strcmp(operation, "asin") == 0) return mpfr_asin(output, left, rounding);
  if (strcmp(operation, "acos") == 0) return mpfr_acos(output, left, rounding);
  if (strcmp(operation, "atan") == 0) return mpfr_atan(output, left, rounding);
  if (strcmp(operation, "atan2") == 0)
    return mpfr_atan2(output, left, right, rounding);
  if (strcmp(operation, "sinh") == 0) return mpfr_sinh(output, left, rounding);
  if (strcmp(operation, "cosh") == 0) return mpfr_cosh(output, left, rounding);
  if (strcmp(operation, "tanh") == 0) return mpfr_tanh(output, left, rounding);
  if (strcmp(operation, "asinh") == 0)
    return mpfr_asinh(output, left, rounding);
  if (strcmp(operation, "acosh") == 0)
    return mpfr_acosh(output, left, rounding);
  if (strcmp(operation, "atanh") == 0)
    return mpfr_atanh(output, left, rounding);
  fprintf(stderr, "unsupported operation: %s\n", operation);
  exit(2);
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

static long parse_positive(const char *text, const char *name) {
  char *end = NULL;
  errno = 0;
  long value = strtol(text, &end, 10);
  if (errno != 0 || end == text || *end != '\0' || value <= 0) {
    fprintf(stderr, "%s must be a positive integer\n", name);
    exit(2);
  }
  return value;
}

int main(int argc, char **argv) {
  long cases_per_cell = 4;
  uint64_t seed = UINT64_C(20260715);
  if (argc >= 2) cases_per_cell = parse_positive(argv[1], "cases-per-cell");
  if (argc >= 3) seed = (uint64_t)parse_positive(argv[2], "seed");
  if (argc > 3) {
    fprintf(stderr, "usage: %s [cases-per-cell] [seed]\n", argv[0]);
    return 2;
  }
  printf("# mpfr-elementary-v1 mpfr=%s cases-per-cell=%ld seed=%llu\n",
         mpfr_get_version(), cases_per_cell, (unsigned long long)seed);
  puts("# operation precision rounding left right integer expected inexact invalid division_by_zero");

  mpfr_t left;
  mpfr_t right;
  mpfr_t output;
  mpfr_init2(left, 512);
  mpfr_init2(right, 512);
  mpfr_init2(output, 2);
  uint64_t state = seed;
  size_t operation_count = sizeof(operations) / sizeof(operations[0]);
  size_t precision_count = sizeof(precisions) / sizeof(precisions[0]);
  size_t rounding_count = sizeof(roundings) / sizeof(roundings[0]);
  for (size_t operation_index = 0; operation_index < operation_count;
       ++operation_index) {
    for (size_t precision_index = 0; precision_index < precision_count;
         ++precision_index) {
      mpfr_set_prec(output, precisions[precision_index]);
      for (size_t rounding_index = 0; rounding_index < rounding_count;
           ++rounding_index) {
        for (long case_index = 0; case_index < cases_per_cell; ++case_index) {
          long integer = 0;
          make_operands(operations[operation_index].name, left, right, &integer,
                        &state);
          mpfr_clear_flags();
          int ternary;
          if (rounding_index == 1) {
            mpfr_round_nearest_away_begin(output);
            ternary = evaluate(operations[operation_index].name, output, left,
                               right, integer, MPFR_RNDN);
            ternary = mpfr_round_nearest_away_end(output, ternary);
          } else {
            ternary = evaluate(operations[operation_index].name, output, left,
                               right, integer, roundings[rounding_index]);
          }
          printf("%s %ld %s ", operations[operation_index].name,
                 (long)precisions[precision_index],
                 rounding_names[rounding_index]);
          print_hex(left);
          fputc(' ', stdout);
          if (operations[operation_index].arity == 2) {
            print_hex(right);
          } else {
            fputc('-', stdout);
          }
          printf(" %ld ", integer);
          print_hex(output);
          printf(" %d %d %d\n", ternary != 0, mpfr_nanflag_p() != 0,
                 mpfr_divby0_p() != 0);
        }
      }
    }
  }
  mpfr_clear(output);
  mpfr_clear(right);
  mpfr_clear(left);
  return 0;
}
