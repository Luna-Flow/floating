// Standalone reproducer: mpfr_sqrt reports ternary 0 ("exact") for an operand
// that is not a perfect square, and rounds toward +infinity to a value below
// the true root.
//
//   a = 2 * (2^445 + 2^223 + 1)   (odd binary exponent, 447 bits, not a square)
//   y = mpfr_sqrt(a) with precision 444 and rounding mode RNDU
//
// Expected: ternary > 0 and y*y > a. Observed with MPFR 4.2.2: ternary 0 and
// y*y < a (checked here with an exact product, in 2*444 bits).
//
// Build: cc -O1 -I<mpfr>/include -L<mpfr>/lib -o repro \
//          tools/mpfr_sqrt_ternary_repro.c -lmpfr -lgmp
#include <stdio.h>
#include <gmp.h>
#include <mpfr.h>

int main(void) {
  mpz_t z;
  mpz_init(z);
  mpz_setbit(z, 446);  // 2 * 2^445
  mpz_setbit(z, 224);  // 2 * 2^223
  mpz_add_ui(z, z, 2);  // 2 * 1
  mpfr_t a, y, square;
  mpfr_init2(a, 447);
  mpfr_set_z(a, z, MPFR_RNDN);  // exact
  mpfr_init2(y, 444);
  mpfr_init2(square, 2 * 444);
  int ternary = mpfr_sqrt(y, a, MPFR_RNDU);
  mpfr_mul(square, y, y, MPFR_RNDN);  // exact: 2*444 bits
  int cmp = mpfr_cmp(square, a);
  printf("MPFR %s, GMP %s\n", mpfr_get_version(), gmp_version);
  printf("ternary = %d (expected > 0)\n", ternary);
  printf("y*y %s a (expected >)\n", cmp == 0 ? "==" : (cmp < 0 ? "<" : ">"));
  mpfr_printf("y = %Ra\n", y);
  return !(ternary == 0 && cmp < 0);  // exit 1 only if the defect is absent
}
