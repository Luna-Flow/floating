/*
 * MPFR enclosures of sin, cos and tan at an integer-valued decimal operand of
 * huge magnitude, for tools/generate_decimal_huge_trig_rows.py.
 *
 * tools/mpfr_decimal_enclosure.c brackets a decimal operand by its 2048-bit
 * values, which is far too wide a box for 1E+300000 (an argument of 10^6 bits
 * needs the operand exactly). Here the operand `a` (a decimal literal whose
 * value is an integer) is set at a precision that holds it exactly (checked by
 * the ternary value of mpfr_set_str), and the function is evaluated at 768 bits
 * with RNDD and RNDU.
 *
 * An operand `2^k` (k a decimal integer) is the exact power of two.
 *
 * Reads lines `operation operand` on stdin, writes `lower upper` as decimal
 * literals of 90 significant digits (`RNDD` and `RNDU` of the 768-bit results),
 * or `skip`. MPFR is an oracle, not an authority.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gmp.h>
#include <mpfr.h>

#define RESULT_PRECISION 768

static int evaluate(const char *op, mpfr_t out, const mpfr_t x, mpfr_rnd_t r) {
  if (strcmp(op, "sin") == 0) return mpfr_sin(out, x, r);
  if (strcmp(op, "cos") == 0) return mpfr_cos(out, x, r);
  if (strcmp(op, "tan") == 0) return mpfr_tan(out, x, r);
  return -1;
}

int main(void) {
  char op[32];
  static char operand[2000000];
  while (scanf("%31s %1999999s", op, operand) == 2) {
    size_t length = strlen(operand);
    /* digits * log2(10) bits, plus the exponent part of 1E+n, plus slack. */
    long exponent = 0;
    const char *e = strchr(operand, 'E');
    if (e != NULL) exponent = atol(e + 1);
    long bits = (long)((length + (exponent > 0 ? exponent : 0)) * 3.33) + 128;
    mpfr_t x, lo, hi;
    int power_of_two = operand[0] == '2' && operand[1] == '^';
    if (power_of_two) bits = 64;
    mpfr_init2(x, bits);
    mpfr_init2(lo, RESULT_PRECISION);
    mpfr_init2(hi, RESULT_PRECISION);
    if (power_of_two) {
      mpfr_set_ui_2exp(x, 1, atol(operand + 2), MPFR_RNDN);
    }
    if (!power_of_two && mpfr_set_str(x, operand, 10, MPFR_RNDN) != 0) {
      puts("skip");
    } else {
      evaluate(op, lo, x, MPFR_RNDD);
      evaluate(op, hi, x, MPFR_RNDU);
      mpfr_printf("%.90RDe %.90RUe\n", lo, hi);
    }
    fflush(stdout);
    mpfr_clear(x);
    mpfr_clear(lo);
    mpfr_clear(hi);
  }
  return 0;
}
