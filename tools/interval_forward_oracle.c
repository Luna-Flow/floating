/*
 * MPFR values for tools/interval_forward_oracle.py (tests of the interval package).
 *
 * Reads rows `op precision x [y]` (x and y exact, hexadecimal as `[-]0x<hex>p<exp>`, parsed exactly)
 * and writes, per row, `lo hi`: the two directed roundings (RNDD, RNDU) of op(x) or op(x, y) to
 * `precision` bits as MPFR writes them (`%Ra`). Operations: asin acos atan tan cot pow atan2 (first operand the ordinate).
 * Nothing of it is shared with `binary` or `interval`.
 *
 *   interval_forward_oracle INPUT OUTPUT
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <gmp.h>
#include <mpfr.h>

static void die(const char *message) {
  fprintf(stderr, "interval_forward_oracle: %s\n", message);
  exit(2);
}

static void read_exact(mpfr_t value, const char *text) {
  char *end = NULL;
  mpfr_set_prec(value, 4096);
  if (mpfr_strtofr(value, text, &end, 16, MPFR_RNDN) != 0 || *end != '\0') die("operand is not exact");
}

static int apply(const char *op, mpfr_t out, mpfr_t x, mpfr_t y, mpfr_rnd_t rnd) {
  if (strcmp(op, "asin") == 0) return mpfr_asin(out, x, rnd);
  if (strcmp(op, "acos") == 0) return mpfr_acos(out, x, rnd);
  if (strcmp(op, "atan") == 0) return mpfr_atan(out, x, rnd);
  if (strcmp(op, "tan") == 0) return mpfr_tan(out, x, rnd);
  if (strcmp(op, "cot") == 0) return mpfr_cot(out, x, rnd);
  if (strcmp(op, "pow") == 0) return mpfr_pow(out, x, y, rnd);
  if (strcmp(op, "atan2") == 0) return mpfr_atan2(out, x, y, rnd); /* atan2(y = first, x = second) */
  die("unknown operation");
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 3) die("usage: INPUT OUTPUT");
  FILE *in = fopen(argv[1], "r");
  FILE *out = fopen(argv[2], "w");
  if (!in || !out) die("cannot open files");
  char line[4096];
  mpfr_t x, y, lo, hi;
  mpfr_inits2(4096, x, y, (mpfr_ptr)0);
  mpfr_init2(lo, 2);
  mpfr_init2(hi, 2);
  while (fgets(line, sizeof line, in)) {
    if (line[0] == '#' || line[0] == '\n') continue;
    char op[16], xs[2048], ys[2048];
    long precision;
    int n = sscanf(line, "%15s %ld %2047s %2047s", op, &precision, xs, ys);
    if (n < 3) die("bad row");
    read_exact(x, xs);
    if (n == 4) read_exact(y, ys);
    mpfr_set_prec(lo, precision);
    mpfr_set_prec(hi, precision);
    apply(op, lo, x, y, MPFR_RNDD);
    apply(op, hi, x, y, MPFR_RNDU);
    mpfr_fprintf(out, "%Ra %Ra\n", lo, hi);
  }
  fclose(in);
  fclose(out);
  return 0;
}
