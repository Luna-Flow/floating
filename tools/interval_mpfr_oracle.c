/*
 * Oracle of the differential stage of `Interval` against MPFR (tools/interval_diff.py).
 *
 * Reads rows `id op size class operand...` (an operand is `lo:hi`, two values
 * written as the library writes them, see tools/mpfr_ours.h) and writes, for
 * every row, the tightest result interval of `size` bits, computed with MPFR
 * directly: every bound is one MPFR operation with a directed rounding on the
 * bounds of the operands (the extremum of a monotone or multi-affine function is
 * attained at a bound), in the exponent range and with the gradual underflow of
 * `binary` (tools/mpfr_ours.h). Nothing of it is shared with `binary` or
 * `interval`; it shares MPFR with MPFI.
 *
 *   interval_mpfr_oracle INPUT OUTPUT
 *
 * Output rows: `id lo hi flags echo lohex hihex` (the hexadecimal texts of the bounds are
 * for the operations whose result is only required to enclose, see the test). `lo` and `hi` are canonical texts;
 * `echo` is the canonical text of every operand bound after the outward
 * rounding to `size` bits, `lo:hi,lo:hi`, so that the library's reading of the
 * same text can be checked; `flags` is `-` or a subset of `o` (a bound
 * overflowed), `s` (a bound is in the subnormal band), `z` (a bound underflowed
 * to zero), `i` (an operand bound is in the subnormal band), `u` (undecided: MPFR's
 * answer failed an exact check, see sqrt_down_ok).
 */
#define _POSIX_C_SOURCE 200809L
#include "mpfr_ours.h"

#define MAX_OPERANDS 3

typedef struct {
  mpfr_t lo, hi;
} ival;

static void die(const char *message) {
  fprintf(stderr, "interval_mpfr_oracle: %s\n", message);
  exit(2);
}

/* The state of one row's computation. */
static unsigned row_flags;
#define F_OVERFLOW 1u
#define F_SUBNORMAL 2u
#define F_ZERO 4u
#define F_UNDECIDED 8u
#define F_SUBNORMAL_OPERAND 16u

static void note_result(const mpfr_t y, int overflowed, int underflowed) {
  if (overflowed) row_flags |= F_OVERFLOW;
  if (mpfr_regular_p(y) && mpfr_get_exp(y) <= OURS_EMIN) row_flags |= F_SUBNORMAL;
  if (underflowed || mpfr_zero_p(y)) {
    if (underflowed) row_flags |= F_ZERO;
  }
}

/* y = a op b, rounded in direction rnd, in the range of the library. */
typedef int (*op2_t)(mpfr_t, const mpfr_t, const mpfr_t, mpfr_rnd_t);

static void directed2(mpfr_t y, op2_t op, const mpfr_t a, const mpfr_t b, mpfr_rnd_t rnd) {
  mpfr_clear_flags();
  int ternary = op(y, a, b, rnd);
  int over = mpfr_overflow_p() != 0;
  int under = mpfr_underflow_p() != 0;
  ours_subnormalize(y, ternary, rnd);
  note_result(y, over, under);
}

static int op_add(mpfr_t y, const mpfr_t a, const mpfr_t b, mpfr_rnd_t r) { return mpfr_add(y, a, b, r); }
static int op_sub(mpfr_t y, const mpfr_t a, const mpfr_t b, mpfr_rnd_t r) { return mpfr_sub(y, a, b, r); }
static int op_mul(mpfr_t y, const mpfr_t a, const mpfr_t b, mpfr_rnd_t r) { return mpfr_mul(y, a, b, r); }
static int op_div(mpfr_t y, const mpfr_t a, const mpfr_t b, mpfr_rnd_t r) { return mpfr_div(y, a, b, r); }

/* lo = min, hi = max over the candidates `lows` (each rounded down) and `highs` (each rounded up). */
static void take_min(mpfr_t acc, int *have, const mpfr_t x) {
  if (!*have || mpfr_cmp(x, acc) < 0) mpfr_set(acc, x, MPFR_RNDN);
  *have = 1;
}
static void take_max(mpfr_t acc, int *have, const mpfr_t x) {
  if (!*have || mpfr_cmp(x, acc) > 0) mpfr_set(acc, x, MPFR_RNDN);
  *have = 1;
}

static void corners2(op2_t op, const ival *a, const ival *b, long p, ival *out) {
  mpfr_t t;
  mpfr_init2(t, p);
  int have_lo = 0, have_hi = 0;
  const mpfr_t *av[2] = {&a->lo, &a->hi};
  const mpfr_t *bv[2] = {&b->lo, &b->hi};
  for (int i = 0; i < 2; i++)
    for (int j = 0; j < 2; j++) {
      directed2(t, op, *av[i], *bv[j], MPFR_RNDD);
      take_min(out->lo, &have_lo, t);
      directed2(t, op, *av[i], *bv[j], MPFR_RNDU);
      take_max(out->hi, &have_hi, t);
    }
  mpfr_clear(t);
}

static void compute_add(const ival *a, const ival *b, long p, ival *out) {
  (void)p;
  directed2(out->lo, op_add, a->lo, b->lo, MPFR_RNDD);
  directed2(out->hi, op_add, a->hi, b->hi, MPFR_RNDU);
}
static void compute_sub(const ival *a, const ival *b, long p, ival *out) {
  (void)p;
  directed2(out->lo, op_sub, a->lo, b->hi, MPFR_RNDD);
  directed2(out->hi, op_sub, a->hi, b->lo, MPFR_RNDU);
}

static void directed_sqr(mpfr_t y, const mpfr_t a, mpfr_rnd_t rnd) {
  directed2(y, op_mul, a, a, rnd);
}

static void compute_sqr(const ival *a, long p, ival *out) {
  (void)p;
  if (mpfr_sgn(a->lo) >= 0) {
    directed_sqr(out->lo, a->lo, MPFR_RNDD);
    directed_sqr(out->hi, a->hi, MPFR_RNDU);
  } else if (mpfr_sgn(a->hi) <= 0) {
    directed_sqr(out->lo, a->hi, MPFR_RNDD);
    directed_sqr(out->hi, a->lo, MPFR_RNDU);
  } else {
    mpfr_set_ui(out->lo, 0, MPFR_RNDN);
    mpfr_t x, y;
    mpfr_init2(x, mpfr_get_prec(out->hi));
    mpfr_init2(y, mpfr_get_prec(out->hi));
    directed_sqr(x, a->lo, MPFR_RNDU);
    directed_sqr(y, a->hi, MPFR_RNDU);
    mpfr_set(out->hi, mpfr_cmp(x, y) >= 0 ? x : y, MPFR_RNDN);
    mpfr_clear(x);
    mpfr_clear(y);
  }
}

/*
 * mpfr_sqrt of MPFR 4.2.2 (the Homebrew build) returns for some operands a value
 * on the wrong side of the root or a wrong ternary value (see
 * testdata/binary/README.md, "Known oracle defect"). The row is checked with an
 * exact product: `r` is the rounded-down root of `a` when r*r <= a < next(r)^2, the
 * rounded-up one when prev(r)^2 < a <= r*r. A row that fails is undecided.
 */
static int sqrt_down_ok(const mpfr_t r, const mpfr_t a) {
  if (mpfr_zero_p(a)) return mpfr_zero_p(r);
  long p = (long)mpfr_get_prec(r);
  mpfr_t t, n;
  mpfr_init2(t, 2 * p + 2);
  mpfr_init2(n, p);
  mpfr_set(n, r, MPFR_RNDN);
  ours_range_wide();
  mpfr_mul(t, r, r, MPFR_RNDN);
  int ok = mpfr_cmp(t, a) <= 0;
  mpfr_nextabove(n);
  mpfr_mul(t, n, n, MPFR_RNDN);
  ok = ok && mpfr_cmp(t, a) > 0;
  mpfr_clear(t);
  mpfr_clear(n);
  return ok;
}
static int sqrt_up_ok(const mpfr_t r, const mpfr_t a) {
  if (mpfr_zero_p(a)) return mpfr_zero_p(r);
  long p = (long)mpfr_get_prec(r);
  mpfr_t t, n;
  mpfr_init2(t, 2 * p + 2);
  mpfr_init2(n, p);
  mpfr_set(n, r, MPFR_RNDN);
  ours_range_wide();
  mpfr_mul(t, r, r, MPFR_RNDN);
  int ok = mpfr_cmp(t, a) >= 0;
  mpfr_nextbelow(n);
  mpfr_mul(t, n, n, MPFR_RNDN);
  ok = ok && mpfr_cmp(t, a) < 0;
  mpfr_clear(t);
  mpfr_clear(n);
  return ok;
}

static void compute_sqrt(const ival *a, long p, ival *out) {
  if (mpfr_sgn(a->lo) < 0) die("sqrt of an interval below zero is not a row of this stage");
  mpfr_clear_flags();
  int t1 = mpfr_sqrt(out->lo, a->lo, MPFR_RNDD);
  int t2 = mpfr_sqrt(out->hi, a->hi, MPFR_RNDU);
  (void)t1;
  (void)t2;
  int ok = sqrt_down_ok(out->lo, a->lo) && sqrt_up_ok(out->hi, a->hi);
  ours_range_enter(p);
  if (!ok) row_flags |= F_UNDECIDED;
  note_result(out->lo, 0, 0);
  note_result(out->hi, 0, 0);
}

static void compute_fma(const ival *a, const ival *b, const ival *c, long p, ival *out) {
  mpfr_t t;
  mpfr_init2(t, p);
  int have_lo = 0, have_hi = 0;
  const mpfr_t *av[2] = {&a->lo, &a->hi};
  const mpfr_t *bv[2] = {&b->lo, &b->hi};
  const mpfr_t *cv[2] = {&c->lo, &c->hi};
  for (int i = 0; i < 2; i++)
    for (int j = 0; j < 2; j++)
      for (int k = 0; k < 2; k++) {
        mpfr_clear_flags();
        int tern = mpfr_fma(t, *av[i], *bv[j], *cv[k], MPFR_RNDD);
        int over = mpfr_overflow_p() != 0, under = mpfr_underflow_p() != 0;
        ours_subnormalize(t, tern, MPFR_RNDD);
        note_result(t, over, under);
        take_min(out->lo, &have_lo, t);
        mpfr_clear_flags();
        tern = mpfr_fma(t, *av[i], *bv[j], *cv[k], MPFR_RNDU);
        over = mpfr_overflow_p() != 0;
        under = mpfr_underflow_p() != 0;
        ours_subnormalize(t, tern, MPFR_RNDU);
        note_result(t, over, under);
        take_max(out->hi, &have_hi, t);
      }
  mpfr_clear(t);
}

/* exp and ln are increasing: one directed evaluation per bound. */
typedef int (*op1_t)(mpfr_t, const mpfr_t, mpfr_rnd_t);

static void directed1(mpfr_t y, op1_t op, const mpfr_t a, mpfr_rnd_t rnd) {
  mpfr_clear_flags();
  int ternary = op(y, a, rnd);
  int over = mpfr_overflow_p() != 0;
  int under = mpfr_underflow_p() != 0;
  ours_subnormalize(y, ternary, rnd);
  note_result(y, over, under);
}

static void compute_increasing(op1_t op, const ival *a, ival *out) {
  directed1(out->lo, op, a->lo, MPFR_RNDD);
  directed1(out->hi, op, a->hi, MPFR_RNDU);
}

static int op_exp(mpfr_t y, const mpfr_t a, mpfr_rnd_t r) { return mpfr_exp(y, a, r); }
static int op_log(mpfr_t y, const mpfr_t a, mpfr_rnd_t r) { return mpfr_log(y, a, r); }

/* Reading and outward rounding of the operands. */
static void read_operand(ival *x, const char *token, long p) {
  char *copy = strdup(token);
  char *colon = strchr(copy, ':');
  if (colon == NULL) die("operand without ':'");
  *colon = '\0';
  const char *lo_text = copy, *hi_text = colon + 1;
  long bits_lo = ours_text_bits(lo_text), bits_hi = ours_text_bits(hi_text);
  mpfr_t raw;
  ours_range_wide();
  mpfr_init2(raw, bits_lo > bits_hi ? bits_lo : bits_hi);
  mpfr_init2(x->lo, p);
  mpfr_init2(x->hi, p);
  ours_read(raw, lo_text);
  if (mpfr_set(x->lo, raw, MPFR_RNDD) != 0 && 0) die("unreachable");
  ours_read(raw, hi_text);
  mpfr_set(x->hi, raw, MPFR_RNDU);
  mpfr_clear(raw);
  free(copy);
}

static void echo_operand(FILE *out, const ival *x) {
  ours_print(out, x->lo);
  fputc(':', out);
  ours_print(out, x->hi);
}

int main(int argc, char **argv) {
  if (argc != 3) die("usage: interval_mpfr_oracle INPUT OUTPUT");
  FILE *in = fopen(argv[1], "r");
  FILE *out = fopen(argv[2], "w");
  if (in == NULL || out == NULL) die("cannot open the files");
  fprintf(out, "# interval-diff-oracle-v1 mpfr=%s\n", mpfr_get_version());
  char *line = NULL;
  size_t cap = 0;
  while (getline(&line, &cap, in) >= 0) {
    size_t n = strlen(line);
    while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) line[--n] = '\0';
    if (n == 0 || line[0] == '#') continue;
    char *fields[16];
    int count = 0;
    for (char *tok = strtok(line, " "); tok != NULL && count < 16; tok = strtok(NULL, " ")) fields[count++] = tok;
    if (count < 5) die("malformed row");
    const char *id = fields[0], *op = fields[1];
    long p = atol(fields[2]);
    int arity = count - 4;
    if (arity < 1 || arity > MAX_OPERANDS) die("wrong number of operands");
    ival x[MAX_OPERANDS];
    for (int i = 0; i < arity; i++) {
      read_operand(&x[i], fields[4 + i], p);
      row_flags = 0;
    }
    unsigned operand_flags = 0;
    for (int i = 0; i < arity; i++) {
      const mpfr_t *bounds[2] = {&x[i].lo, &x[i].hi};
      for (int k = 0; k < 2; k++)
        if (mpfr_regular_p(*bounds[k]) && mpfr_get_exp(*bounds[k]) <= OURS_EMIN) operand_flags |= F_SUBNORMAL_OPERAND;
    }
    ival r;
    ours_range_wide();
    mpfr_init2(r.lo, p);
    mpfr_init2(r.hi, p);
    row_flags = operand_flags;
    ours_range_enter(p);
    if (strcmp(op, "add") == 0) compute_add(&x[0], &x[1], p, &r);
    else if (strcmp(op, "sub") == 0) compute_sub(&x[0], &x[1], p, &r);
    else if (strcmp(op, "mul") == 0) corners2(op_mul, &x[0], &x[1], p, &r);
    else if (strcmp(op, "div") == 0) corners2(op_div, &x[0], &x[1], p, &r);
    else if (strcmp(op, "sqr") == 0) compute_sqr(&x[0], p, &r);
    else if (strcmp(op, "sqrt") == 0) compute_sqrt(&x[0], p, &r);
    else if (strcmp(op, "exp") == 0) compute_increasing(op_exp, &x[0], &r);
    else if (strcmp(op, "ln") == 0) {
      if (mpfr_sgn(x[0].lo) <= 0) die("ln of an interval that is not positive is not a row of this stage");
      compute_increasing(op_log, &x[0], &r);
    } else if (strcmp(op, "fma") == 0) compute_fma(&x[0], &x[1], &x[2], p, &r);
    else die("unknown operation");
    fprintf(out, "%s ", id);
    ours_print(out, r.lo);
    fputc(' ', out);
    ours_print(out, r.hi);
    fputc(' ', out);
    if (row_flags == 0) {
      fputc('-', out);
    } else {
      if (row_flags & F_OVERFLOW) fputc('o', out);
      if (row_flags & F_SUBNORMAL) fputc('s', out);
      if (row_flags & F_ZERO) fputc('z', out);
      if (row_flags & F_SUBNORMAL_OPERAND) fputc('i', out);
      if (row_flags & F_UNDECIDED) fputc('u', out);
    }
    fputc(' ', out);
    for (int i = 0; i < arity; i++) {
      if (i > 0) fputc(',', out);
      echo_operand(out, &x[i]);
    }
    fputc(' ', out);
    ours_print_hex(out, r.lo);
    fputc(' ', out);
    ours_print_hex(out, r.hi);
    fputc('\n', out);
    for (int i = 0; i < arity; i++) {
      mpfr_clear(x[i].lo);
      mpfr_clear(x[i].hi);
    }
    mpfr_clear(r.lo);
    mpfr_clear(r.hi);
  }
  free(line);
  fclose(in);
  fclose(out);
  return 0;
}
