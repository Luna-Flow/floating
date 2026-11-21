/*
 * MPFR in the exponent range and with the number format of `binary`.
 *
 * Header-only (static functions, no state of its own) so that the C programs
 * that produce oracle values for the library (the differential stage of
 * `tools/interval_diff.py`, the row tables of the elementary and reverse functions)
 * use one definition of:
 *
 *   - reading a value as the library writes it (`[-]0x<hex>p<exp>`, `inf`, `-inf`,
 *     `nan`), exactly;
 *   - the exponent range of the library in MPFR, and the gradual underflow below it;
 *   - the canonical text of a value (the same form as `canonical_binary` of
 *     `tooling/src/bench/external/canonical_test.mbt`);
 *   - containment of one interval in another.
 *
 * The range mapping is the one of `tools/generate_mpfr_random_oracle.c`
 * (`compute_real`), which the binary gate has checked against `Binary`:
 * `binary` has `e_max = 2^30 - 1` for the leading bit (a value below
 * 2^(e_max+1)) and `e_min = 1 - e_max` (the smallest normal number is 2^e_min),
 * with subnormal numbers down to 2^(e_min - precision + 1); MPFR writes a value
 * as 0.1xxx * 2^e, one binade higher at both ends, and has no subnormal numbers.
 * So MPFR's range is set to [e_min - precision + 2, e_max + 1], and a result
 * whose MPFR exponent is at most e_min is put through `mpfr_subnormalize` with
 * the ternary value of the first rounding (exact for the directed modes, which
 * are the only ones used here; round to nearest away is not available).
 */
#ifndef MPFR_OURS_H
#define MPFR_OURS_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <gmp.h>
#include <mpfr.h>

#if defined(__GNUC__) || defined(__clang__)
#define OURS_UNUSED __attribute__((unused))
#else
#define OURS_UNUSED
#endif

#define OURS_EMAX 1073741823L
#define OURS_EMIN (1 - OURS_EMAX)

/* The widest exponent range, for reading operands exactly. */
OURS_UNUSED static void ours_range_wide(void) {
  if (mpfr_set_emin(mpfr_get_emin_min()) || mpfr_set_emax(mpfr_get_emax_max())) {
    fprintf(stderr, "mpfr_ours: cannot widen the exponent range\n");
    exit(2);
  }
}

/* The exponent range of the library for results of `precision` bits. */
OURS_UNUSED static void ours_range_enter(long precision) {
  ours_range_wide();
  if (mpfr_set_emin(OURS_EMIN - precision + 2) || mpfr_set_emax(OURS_EMAX + 1)) {
    fprintf(stderr, "mpfr_ours: range out of MPFR bounds for precision %ld\n", precision);
    exit(2);
  }
}

/*
 * The result of a directed operation `rnd` (MPFR_RNDD or MPFR_RNDU, or RNDZ,
 * RNDA) just rounded into `y` with ternary value `ternary`: the second rounding
 * of the subnormal band. Returns the ternary value of the whole.
 */
OURS_UNUSED static int ours_subnormalize(mpfr_t y, int ternary, mpfr_rnd_t rnd) {
  if (mpfr_regular_p(y) && mpfr_get_exp(y) <= OURS_EMIN)
    return mpfr_subnormalize(y, ternary, rnd);
  return ternary;
}

/* Reads `text` exactly into `y` (whose precision must hold every digit); aborts otherwise. */
OURS_UNUSED static void ours_read(mpfr_t y, const char *text) {
  const char *body = text;
  if (*body == '-' || *body == '+') body++;
  if (strcmp(body, "inf") == 0) {
    mpfr_set_inf(y, *text == '-' ? -1 : 1);
    return;
  }
  if (strcmp(body, "nan") == 0) {
    mpfr_set_nan(y);
    return;
  }
  if (mpfr_set_str(y, text, 0, MPFR_RNDN) != 0 || mpfr_nan_p(y)) {
    fprintf(stderr, "mpfr_ours: cannot read %s exactly at %ld bits\n", text, (long)mpfr_get_prec(y));
    exit(2);
  }
}

/* The number of bits a value written as `text` needs: four per hexadecimal digit. */
OURS_UNUSED static long ours_text_bits(const char *text) {
  const char *p = strstr(text, "0x");
  if (p == NULL) return 2;
  p += 2;
  long digits = 0;
  while (*p != '\0' && *p != 'p' && *p != 'P') {
    if (*p != '.') digits++;
    p++;
  }
  return digits * 4 < 2 ? 2 : digits * 4;
}

/* Canonical text: nan, inf, -inf, 0, -0, or [-]0b<odd integer in binary>p<exponent>. */
OURS_UNUSED static void ours_print(FILE *out, const mpfr_t x) {
  if (mpfr_nan_p(x)) {
    fputs("nan", out);
  } else if (mpfr_inf_p(x)) {
    fputs(mpfr_signbit(x) ? "-inf" : "inf", out);
  } else if (mpfr_zero_p(x)) {
    fputs(mpfr_signbit(x) ? "-0" : "0", out);
  } else {
    mpz_t m;
    mpz_init(m);
    mpfr_exp_t e = mpfr_get_z_2exp(m, x);
    int negative = mpz_sgn(m) < 0;
    mpz_abs(m, m);
    mp_bitcnt_t tz = mpz_scan1(m, 0);
    mpz_tdiv_q_2exp(m, m, tz);
    char *digits = mpz_get_str(NULL, 2, m);
    fprintf(out, "%s0b%sp%ld", negative ? "-" : "", digits, (long)e + (long)tz);
    void (*freefunc)(void *, size_t);
    mp_get_memory_functions(NULL, NULL, &freefunc);
    freefunc(digits, strlen(digits) + 1);
    mpz_clear(m);
  }
}

/* The same value as `[-]0x<hex>p<exponent>`, `inf`, `-inf`, `nan`, `0x0p0`, `-0x0p0`: the text the library reads (Binary::from_hex). */
OURS_UNUSED static void ours_print_hex(FILE *out, const mpfr_t x) {
  if (mpfr_nan_p(x)) {
    fputs("nan", out);
  } else if (mpfr_inf_p(x)) {
    fputs(mpfr_signbit(x) ? "-inf" : "inf", out);
  } else if (mpfr_zero_p(x)) {
    fputs(mpfr_signbit(x) ? "-0x0p0" : "0x0p0", out);
  } else {
    mpz_t m;
    mpz_init(m);
    mpfr_exp_t e = mpfr_get_z_2exp(m, x);
    int negative = mpz_sgn(m) < 0;
    mpz_abs(m, m);
    char *digits = mpz_get_str(NULL, 16, m);
    fprintf(out, "%s0x%sp%ld", negative ? "-" : "", digits, (long)e);
    void (*freefunc)(void *, size_t);
    mp_get_memory_functions(NULL, NULL, &freefunc);
    freefunc(digits, strlen(digits) + 1);
    mpz_clear(m);
  }
}

/* The two zeros are one number in the set-based interval flavour: compare them as equal. */
OURS_UNUSED static int ours_cmp_endpoint(const mpfr_t a, const mpfr_t b) {
  if (mpfr_zero_p(a) && mpfr_zero_p(b)) return 0;
  if (mpfr_nan_p(a) || mpfr_nan_p(b)) return 2;
  return mpfr_cmp(a, b);
}

/* 1 when [lo_a, hi_a] contains [lo_b, hi_b], exact. */
OURS_UNUSED static int ours_encloses(const mpfr_t lo_a, const mpfr_t hi_a, const mpfr_t lo_b, const mpfr_t hi_b) {
  int c1 = ours_cmp_endpoint(lo_a, lo_b);
  int c2 = ours_cmp_endpoint(hi_a, hi_b);
  return c1 != 2 && c2 != 2 && c1 <= 0 && c2 >= 0;
}

#endif
