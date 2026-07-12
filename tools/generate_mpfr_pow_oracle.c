#include <mpfr.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
  const char *coefficient;
  long exponent2;
  int negative;
  long exponent;
} PowCase;

static const PowCase cases[] = {
  {"3", -1, 0, 3},
  {"5", -2, 1, 7},
  {"7ff", -10, 0, -3},
  {"1000000000000001", -52, 0, 11},
  {"1fffffffffffff", -52, 1, 15},
  {"10000000000000000000000000001", -112, 0, -7},
};

typedef struct {
  const char *name;
  mpfr_rnd_t mode;
} Rounding;

static const Rounding roundings[] = {
  {"n", MPFR_RNDN},
  {"z", MPFR_RNDZ},
  {"u", MPFR_RNDU},
  {"d", MPFR_RNDD},
  {"a", MPFR_RNDA},
};

int main(void) {
  static const mpfr_prec_t precisions[] = {11, 24, 53, 113};
  mpz_t input_integer;
  mpz_t output_integer;
  mpfr_t input;
  mpfr_t output;
  mpz_init(input_integer);
  mpz_init(output_integer);
  mpfr_init2(input, 512);
  mpfr_init2(output, 2);
  puts("# precision rounding input_coefficient_hex input_exponent2 input_negative exponent expected_coefficient_hex expected_exponent2 expected_negative inexact");
  for (size_t precision_index = 0;
       precision_index < sizeof(precisions) / sizeof(precisions[0]);
       precision_index++) {
    mpfr_prec_t precision = precisions[precision_index];
    mpfr_set_prec(output, precision);
    for (size_t rounding_index = 0;
         rounding_index < sizeof(roundings) / sizeof(roundings[0]);
         rounding_index++) {
      for (size_t case_index = 0;
           case_index < sizeof(cases) / sizeof(cases[0]);
           case_index++) {
        const PowCase *test_case = &cases[case_index];
        if (mpz_set_str(input_integer, test_case->coefficient, 16) != 0) {
          return 2;
        }
        mpfr_set_z_2exp(
          input,
          input_integer,
          test_case->exponent2,
          MPFR_RNDN
        );
        if (test_case->negative) {
          mpfr_neg(input, input, MPFR_RNDN);
        }
        mpfr_clear_flags();
        int ternary = mpfr_pow_si(
          output,
          input,
          test_case->exponent,
          roundings[rounding_index].mode
        );
        mpfr_exp_t output_exponent = mpfr_get_z_2exp(output_integer, output);
        int output_negative = mpfr_signbit(output) != 0;
        mpz_abs(output_integer, output_integer);
        char *output_coefficient = mpz_get_str(NULL, 16, output_integer);
        if (output_coefficient == NULL) {
          return 3;
        }
        printf(
          "%ld %s %s %ld %d %ld %s %ld %d %d\n",
          (long) precision,
          roundings[rounding_index].name,
          test_case->coefficient,
          test_case->exponent2,
          test_case->negative,
          test_case->exponent,
          output_coefficient,
          (long) output_exponent,
          output_negative,
          ternary != 0
        );
        free(output_coefficient);
      }
    }
  }
  mpfr_clear(output);
  mpfr_clear(input);
  mpz_clear(output_integer);
  mpz_clear(input_integer);
  return 0;
}
