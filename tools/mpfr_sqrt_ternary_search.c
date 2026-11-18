// Searches for operands on which mpfr_sqrt reports the wrong ternary value or
// a result on the wrong side of the exact root, checked with exact arithmetic
// (y*y against the operand). Operands are a = 2^i + 2^j + 1 with j = (i+1)/2 (an exact
// integer with i+1 bits) times 2^s with s = 0 or 1 (an odd binary exponent changes the
// algorithm's path), output precisions p near i+1, all five rounding modes.
//
// Build: cc -O1 -I<mpfr>/include -L<mpfr>/lib -o search \
//          tools/mpfr_sqrt_ternary_search.c -lmpfr -lgmp
#include <stdio.h>
#include <gmp.h>
#include <mpfr.h>

int main(void) {
  const char *names[] = {"RNDN", "RNDZ", "RNDU", "RNDD", "RNDA"};
  mpfr_rnd_t modes[] = {MPFR_RNDN, MPFR_RNDZ, MPFR_RNDU, MPFR_RNDD, MPFR_RNDA};
  long reported = 0;
  printf("MPFR %s, GMP %s\n", mpfr_get_version(), gmp_version);
  for (long i = 3; i < 1500 && reported < 12; ++i) {
    for (long j = (i + 1) / 2; j <= (i + 1) / 2 && reported < 12; ++j) {
      mpz_t z;
      mpz_init(z);
      mpz_setbit(z, i);
      mpz_setbit(z, j);
      mpz_add_ui(z, z, j == 0 ? 0 : 1);
      mpfr_t a, y, sq;
      mpfr_init2(a, i + 2);
      mpfr_set_z(a, z, MPFR_RNDN);
      mpz_clear(z);
      for (int shift = 0; shift < 2; ++shift) {
      mpfr_mul_2ui(a, a, shift, MPFR_RNDN);
      for (long p = i - 2; p <= i + 4 && p >= 2; ++p) {
        mpfr_init2(y, p);
        mpfr_init2(sq, 2 * p + 4);
        for (int m = 0; m < 5; ++m) {
          int t = mpfr_sqrt(y, a, modes[m]);
          mpfr_mul(sq, y, y, MPFR_RNDN);
          int cmp = mpfr_cmp(sq, a);  // sign of y^2 - a: sign of (y - root)
          int bad = ((cmp == 0) != (t == 0)) ||
                    ((m == 1 || m == 3) && cmp > 0) ||
                    ((m == 2 || m == 4) && cmp < 0) ||
                    (cmp != 0 && t != 0 && ((cmp < 0) != (t < 0)));
          if (bad && reported < 12) {
            printf("a=2^%ld+2^%ld+1 (times 2^%d) p=%ld %s ternary=%d y*y%sa\n", i, j,
                 shift, p, names[m], t, cmp == 0 ? "==" : (cmp < 0 ? "<" : ">"));
            ++reported;
          }
        }
        mpfr_clear(y);
        mpfr_clear(sq);
      }
      mpfr_div_2ui(a, a, shift, MPFR_RNDN);
      }
      mpfr_clear(a);
    }
  }
  printf("%ld mismatches reported\n", reported);
  return 0;
}
