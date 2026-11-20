/*
 * External performance baseline harness (issue #20).
 *
 * Times MPFR (binary) and libmpdec (`decimal_gda`) on the exact operand file that
 * the floating benchmarks read, with the measurement protocol of the
 * Maremark harness (warm-up, calibrated batches, exploratory then
 * confirmatory blocks) so that both sides are measured the same way.
 *
 * Build and run through `just bench external ...` (tools/external_baseline.py);
 * see doc/manual/performance/external_baseline.md for what is timed.
 *
 *   extbench info
 *   extbench reference --inputs FILE --out FILE [--cases LIST]
 *   extbench time --inputs FILE --out FILE [--cases LIST] [protocol options]
 *
 * A case is `kind/op/size` (for example `binary/add/53`, `decimal_gda/ln/34`).
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <gmp.h>
#include <mpdecimal.h>
#include <mpfr.h>

#ifndef EXTBENCH_CFLAGS
#define EXTBENCH_CFLAGS "unknown"
#endif

/* ------------------------------------------------------------------ */
/* Clock                                                              */
/* ------------------------------------------------------------------ */

static uint64_t now_ns(void) {
  struct timespec ts;
#ifdef CLOCK_UPTIME_RAW
  clock_gettime(CLOCK_UPTIME_RAW, &ts);
#else
  clock_gettime(CLOCK_MONOTONIC, &ts);
#endif
  return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

/* ------------------------------------------------------------------ */
/* Input file                                                         */
/* ------------------------------------------------------------------ */

typedef struct {
  char kind[16];
  char op[16];
  int size;
  int idx;
  char *a;
  char *b; /* NULL for unary operations */
} Row;

typedef struct {
  Row *rows;
  size_t len;
  size_t cap;
} Inputs;

static void die(const char *message) {
  fprintf(stderr, "extbench: %s\n", message);
  exit(2);
}

static char *dup_token(const char *start, size_t length) {
  char *copy = malloc(length + 1);
  if (copy == NULL) die("out of memory");
  memcpy(copy, start, length);
  copy[length] = '\0';
  return copy;
}

static void load_inputs(const char *path, Inputs *inputs) {
  FILE *file = fopen(path, "r");
  if (file == NULL) die("cannot open the inputs file");
  char *line = NULL;
  size_t line_cap = 0;
  inputs->rows = NULL;
  inputs->len = 0;
  inputs->cap = 0;
  while (getline(&line, &line_cap, file) >= 0) {
    size_t length = strlen(line);
    while (length > 0 && (line[length - 1] == '\n' || line[length - 1] == '\r'))
      line[--length] = '\0';
    if (length == 0 || line[0] == '#') continue;
    char *fields[6];
    int count = 0;
    char *cursor = line;
    while (count < 6 && cursor != NULL) {
      fields[count++] = cursor;
      char *space = strchr(cursor, ' ');
      if (space != NULL) {
        *space = '\0';
        cursor = space + 1;
      } else {
        cursor = NULL;
      }
    }
    if (count < 5) die("malformed input row");
    if (inputs->len == inputs->cap) {
      inputs->cap = inputs->cap == 0 ? 256 : inputs->cap * 2;
      inputs->rows = realloc(inputs->rows, inputs->cap * sizeof(Row));
      if (inputs->rows == NULL) die("out of memory");
    }
    Row *row = &inputs->rows[inputs->len++];
    snprintf(row->kind, sizeof row->kind, "%s", fields[0]);
    snprintf(row->op, sizeof row->op, "%s", fields[1]);
    row->size = atoi(fields[2]);
    row->idx = atoi(fields[3]);
    row->a = dup_token(fields[4], strlen(fields[4]));
    row->b = count >= 6 ? dup_token(fields[5], strlen(fields[5])) : NULL;
  }
  free(line);
  fclose(file);
}

/* ------------------------------------------------------------------ */
/* Cases                                                              */
/* ------------------------------------------------------------------ */

typedef struct {
  char kind[16];
  char op[16];
  int size;
} CaseId;

typedef enum {
  OP_ADD,
  OP_MUL,
  OP_DIV,
  OP_SQRT,
  OP_EXP,
  OP_LN,
  OP_SIN
} Op;

static Op parse_op(const char *name) {
  if (strcmp(name, "add") == 0) return OP_ADD;
  if (strcmp(name, "mul") == 0) return OP_MUL;
  if (strcmp(name, "div") == 0) return OP_DIV;
  if (strcmp(name, "sqrt") == 0) return OP_SQRT;
  if (strcmp(name, "exp") == 0) return OP_EXP;
  if (strcmp(name, "ln") == 0) return OP_LN;
  if (strcmp(name, "sin") == 0) return OP_SIN;
  die("unknown operation");
  return OP_ADD;
}

static CaseId parse_case(const char *text) {
  CaseId id;
  char buffer[128];
  snprintf(buffer, sizeof buffer, "%s", text);
  char *first = strchr(buffer, '/');
  if (first == NULL) die("a case is kind/op/size");
  *first = '\0';
  char *second = strchr(first + 1, '/');
  if (second == NULL) die("a case is kind/op/size");
  *second = '\0';
  snprintf(id.kind, sizeof id.kind, "%s", buffer);
  snprintf(id.op, sizeof id.op, "%s", first + 1);
  id.size = atoi(second + 1);
  return id;
}

/* Rows of one case, ordered by idx. */
static size_t select_rows(const Inputs *inputs, const CaseId *id, Row ***out) {
  size_t count = 0;
  for (size_t i = 0; i < inputs->len; i++) {
    const Row *row = &inputs->rows[i];
    if (strcmp(row->kind, id->kind) == 0 && strcmp(row->op, id->op) == 0 &&
        row->size == id->size)
      count++;
  }
  Row **picked = calloc(count == 0 ? 1 : count, sizeof(Row *));
  if (picked == NULL) die("out of memory");
  for (size_t i = 0; i < inputs->len; i++) {
    Row *row = &inputs->rows[i];
    if (strcmp(row->kind, id->kind) == 0 && strcmp(row->op, id->op) == 0 &&
        row->size == id->size) {
      if (row->idx < 0 || (size_t)row->idx >= count) die("row index out of range");
      picked[row->idx] = row;
    }
  }
  for (size_t i = 0; i < count; i++)
    if (picked[i] == NULL) die("missing row index");
  *out = picked;
  return count;
}

/* ------------------------------------------------------------------ */
/* A prepared case: operands parsed, results preallocated             */
/* ------------------------------------------------------------------ */

typedef struct {
  Op op;
  int is_binary;
  size_t n;
  /* binary */
  mpfr_t *ba, *bb, *br;
  /* decimal */
  mpd_t **da, **db, **dr;
  mpd_context_t dctx;
} Prepared;

static void prepare(Prepared *p, const CaseId *id, Row **rows, size_t n) {
  memset(p, 0, sizeof *p);
  p->op = parse_op(id->op);
  p->n = n;
  p->is_binary = strcmp(id->kind, "binary") == 0;
  if (p->is_binary) {
    p->ba = malloc(n * sizeof(mpfr_t));
    p->bb = malloc(n * sizeof(mpfr_t));
    p->br = malloc(n * sizeof(mpfr_t));
    for (size_t i = 0; i < n; i++) {
      mpfr_init2(p->ba[i], id->size);
      mpfr_init2(p->bb[i], id->size);
      mpfr_init2(p->br[i], id->size);
      /* Operands have at most `size` significant bits: parsing is exact. */
      if (mpfr_set_str(p->ba[i], rows[i]->a, 0, MPFR_RNDN) != 0) die("inexact operand a");
      const char *b = rows[i]->b != NULL ? rows[i]->b : rows[i]->a;
      if (mpfr_set_str(p->bb[i], b, 0, MPFR_RNDN) != 0) die("inexact operand b");
    }
  } else {
    mpd_defaultcontext(&p->dctx);
    p->dctx.prec = id->size;
    p->dctx.emax = 999999;
    p->dctx.emin = -999999;
    p->dctx.round = MPD_ROUND_HALF_EVEN;
    p->dctx.traps = 0;
    p->dctx.clamp = 0;
    p->dctx.allcr = 1; /* correctly rounded exp and ln in all cases */
    p->da = malloc(n * sizeof(mpd_t *));
    p->db = malloc(n * sizeof(mpd_t *));
    p->dr = malloc(n * sizeof(mpd_t *));
    for (size_t i = 0; i < n; i++) {
      uint32_t status = 0;
      p->da[i] = mpd_qnew();
      p->db[i] = mpd_qnew();
      p->dr[i] = mpd_qnew();
      mpd_qset_string(p->da[i], rows[i]->a, &p->dctx, &status);
      const char *b = rows[i]->b != NULL ? rows[i]->b : rows[i]->a;
      mpd_qset_string(p->db[i], b, &p->dctx, &status);
      if (status != 0) die("inexact or invalid decimal operand");
    }
  }
}

static void release(Prepared *p) {
  for (size_t i = 0; i < p->n; i++) {
    if (p->is_binary) {
      mpfr_clear(p->ba[i]);
      mpfr_clear(p->bb[i]);
      mpfr_clear(p->br[i]);
    } else {
      mpd_del(p->da[i]);
      mpd_del(p->db[i]);
      mpd_del(p->dr[i]);
    }
  }
  free(p->ba);
  free(p->bb);
  free(p->br);
  free(p->da);
  free(p->db);
  free(p->dr);
}

/* One pass: the operation applied to every operand of the case. */
static void pass(Prepared *p) {
  size_t n = p->n;
  if (p->is_binary) {
    mpfr_t *a = p->ba, *b = p->bb, *r = p->br;
    switch (p->op) {
      case OP_ADD:
        for (size_t i = 0; i < n; i++) mpfr_add(r[i], a[i], b[i], MPFR_RNDN);
        break;
      case OP_MUL:
        for (size_t i = 0; i < n; i++) mpfr_mul(r[i], a[i], b[i], MPFR_RNDN);
        break;
      case OP_DIV:
        for (size_t i = 0; i < n; i++) mpfr_div(r[i], a[i], b[i], MPFR_RNDN);
        break;
      case OP_SQRT:
        for (size_t i = 0; i < n; i++) mpfr_sqrt(r[i], a[i], MPFR_RNDN);
        break;
      case OP_EXP:
        for (size_t i = 0; i < n; i++) mpfr_exp(r[i], a[i], MPFR_RNDN);
        break;
      case OP_LN:
        for (size_t i = 0; i < n; i++) mpfr_log(r[i], a[i], MPFR_RNDN);
        break;
      case OP_SIN:
        for (size_t i = 0; i < n; i++) mpfr_sin(r[i], a[i], MPFR_RNDN);
        break;
    }
  } else {
    mpd_t **a = p->da, **b = p->db, **r = p->dr;
    mpd_context_t *ctx = &p->dctx;
    uint32_t status = 0;
    switch (p->op) {
      case OP_ADD:
        for (size_t i = 0; i < n; i++) mpd_qadd(r[i], a[i], b[i], ctx, &status);
        break;
      case OP_MUL:
        for (size_t i = 0; i < n; i++) mpd_qmul(r[i], a[i], b[i], ctx, &status);
        break;
      case OP_DIV:
        for (size_t i = 0; i < n; i++) mpd_qdiv(r[i], a[i], b[i], ctx, &status);
        break;
      case OP_SQRT:
        for (size_t i = 0; i < n; i++) mpd_qsqrt(r[i], a[i], ctx, &status);
        break;
      case OP_EXP:
        for (size_t i = 0; i < n; i++) mpd_qexp(r[i], a[i], ctx, &status);
        break;
      case OP_LN:
        for (size_t i = 0; i < n; i++) mpd_qln(r[i], a[i], ctx, &status);
        break;
      case OP_SIN:
        die("libmpdec has no sin");
        break;
    }
    (void)status;
  }
}

/*
 * The null pass: the loop of `pass` with the library call removed.  It makes
 * the same operand and result accesses (the three operand pointers of every
 * row, and the context and status of the decimal calls) and hands them to an
 * empty asm statement, so the compiler can neither drop the loads nor fuse the
 * loop.  What it cannot remove is stated in the design page: the call and
 * return of the library function stay in the net time of a case.
 */
static void pass_null(Prepared *p) {
  size_t n = p->n;
  if (p->is_binary) {
    mpfr_t *a = p->ba, *b = p->bb, *r = p->br;
    for (size_t i = 0; i < n; i++)
      __asm__ volatile("" : : "r"(a[i]), "r"(b[i]), "r"(r[i]) : "memory");
  } else {
    mpd_t **a = p->da, **b = p->db, **r = p->dr;
    mpd_context_t *ctx = &p->dctx;
    uint32_t status = 0;
    for (size_t i = 0; i < n; i++)
      __asm__ volatile("" : : "r"(a[i]), "r"(b[i]), "r"(r[i]), "r"(ctx), "r"(&status) : "memory");
  }
}

/* ------------------------------------------------------------------ */
/* Reference mode: print the correctly rounded results                */
/* ------------------------------------------------------------------ */

static void reference_case(FILE *out, const CaseId *id, Prepared *p) {
  pass(p);
  for (size_t i = 0; i < p->n; i++) {
    if (p->is_binary) {
      char *text = NULL;
      if (mpfr_asprintf(&text, "%Ra", p->br[i]) < 0) die("mpfr_asprintf failed");
      fprintf(out, "%s %s %d %zu %s\n", id->kind, id->op, id->size, i, text);
      mpfr_free_str(text);
    } else {
      char *text = mpd_to_sci(p->dr[i], 0);
      fprintf(out, "%s %s %d %zu %s\n", id->kind, id->op, id->size, i, text);
      mpd_free(text);
    }
  }
}

/* ------------------------------------------------------------------ */
/* Time mode: the Maremark protocol                                   */
/* ------------------------------------------------------------------ */

typedef struct {
  int warmup_iterations;
  double warmup_time_us;
  double target_batch_time_us;
  int min_batch_iterations;
  int max_batch_iterations;
  double max_sample_time_us;
  int exploratory;
  int confirmatory;
} Protocol;

static double run_batch(Prepared *p, long iterations, int null_variant) {
  uint64_t start = now_ns();
  if (null_variant) {
    for (long i = 0; i < iterations; i++) pass_null(p);
  } else {
    for (long i = 0; i < iterations; i++) pass(p);
  }
  uint64_t end = now_ns();
  return (double)(end - start) / 1000.0;
}

/* Warm-up and calibration of one variant (the case itself, or its null). */
static long calibrate(FILE *out, const CaseId *id, Prepared *p, const Protocol *proto, int round,
                      int null_variant) {
  /* Warm-up: single passes until both the count and the time are reached. */
  int warmup_id = 0;
  double warmup_elapsed = 0.0;
  int limit = proto->warmup_iterations > proto->max_batch_iterations
                  ? proto->warmup_iterations
                  : proto->max_batch_iterations;
  while ((warmup_id < proto->warmup_iterations || warmup_elapsed < proto->warmup_time_us) &&
         warmup_id < limit) {
    warmup_elapsed += run_batch(p, 1, null_variant);
    warmup_id++;
  }
  /* Calibration: the Maremark rule (grow the batch towards the target time). */
  long maximum = proto->max_batch_iterations > 1 ? proto->max_batch_iterations : 1;
  long iterations = proto->min_batch_iterations > 1 ? proto->min_batch_iterations : 1;
  if (iterations > maximum) iterations = maximum;
  long retries = 0;
  double elapsed = run_batch(p, iterations, null_variant);
  while (elapsed < proto->target_batch_time_us && elapsed < proto->max_sample_time_us &&
         iterations < maximum) {
    long estimated = elapsed <= 0.0
                         ? iterations * 10
                         : (long)(((double)iterations * proto->target_batch_time_us / elapsed) + 0.999999999);
    long next = estimated > iterations + 1 ? estimated : iterations + 1;
    if (next > maximum) next = maximum;
    if (next == iterations) break;
    iterations = next;
    retries++;
    elapsed = run_batch(p, iterations, null_variant);
  }
  fprintf(out,
          "{\"type\":\"calibration\",\"tool\":\"%s\",\"round\":%d,\"case\":\"%s/%s/%d\","
          "\"variant\":\"%s\",\"iterations\":%ld,\"elapsed_us\":%.3f,\"retries\":%ld}\n",
          p->is_binary ? "mpfr" : "libmpdec", round, id->kind, id->op, id->size,
          null_variant ? "null" : "case", iterations, elapsed, retries);
  return iterations;
}

/*
 * One case: each block is a pair, a block of the case and a block of its null
 * (each with its own calibrated batch), run back to back.  The order inside a
 * pair alternates with the block index and the round, so each order occurs
 * equally often.  Both blocks of a pair are written with the same block
 * number and the `null_first` flag.
 */
static void time_case(FILE *out, const CaseId *id, Prepared *p, const Protocol *proto,
                      int round) {
  long case_iterations = calibrate(out, id, p, proto, round, 0);
  long null_iterations = calibrate(out, id, p, proto, round, 1);
  int blocks = proto->exploratory + proto->confirmatory;
  for (int block = 0; block < blocks; block++) {
    int null_first = (block + round) % 2;
    double us[2] = {0.0, 0.0}; /* [0] case, [1] null */
    for (int step = 0; step < 2; step++) {
      int null_variant = null_first ? (step == 0) : (step == 1);
      us[null_variant] = run_batch(p, null_variant ? null_iterations : case_iterations, null_variant);
    }
    int exploratory = block < proto->exploratory;
    for (int null_variant = 0; null_variant < 2; null_variant++) {
      fprintf(out,
              "{\"type\":\"observation\",\"tool\":\"%s\",\"round\":%d,\"case\":\"%s/%s/%d\","
              "\"variant\":\"%s\",\"null_first\":%s,"
              "\"phase\":\"%s\",\"block\":%d,\"iterations\":%ld,\"ops_per_iteration\":%zu,"
              "\"elapsed_us\":%.3f}\n",
              p->is_binary ? "mpfr" : "libmpdec", round, id->kind, id->op, id->size,
              null_variant ? "null" : "case", null_first ? "true" : "false",
              exploratory ? "exploratory" : "confirmatory",
              exploratory ? block : block - proto->exploratory,
              null_variant ? null_iterations : case_iterations, p->n, us[null_variant]);
    }
  }
  fflush(out);
}

/* ------------------------------------------------------------------ */
/* Driver                                                             */
/* ------------------------------------------------------------------ */

static void print_info(void) {
  printf("{\"mpfr_version\":\"%s\",\"mpfr_header_version\":\"%s\",\"gmp_version\":\"%s\","
         "\"gmp_header_version\":\"%d.%d.%d\",\"gmp_build_cc\":\"%s\",\"gmp_build_cflags\":\"%s\","
         "\"mpdecimal_version\":\"%s\",\"mpdecimal_header_version\":\"%s\","
         "\"mpfr_tls\":%d,\"mpfr_decimal_p\":%d,"
         "\"mpfr_gmpinternals\":%d,\"mpfr_float128\":%d,\"mpfr_sharedcache\":%d,"
         "\"mpfr_threshold_cache\":\"%s\",\"cflags\":\"%s\",\"cc\":\"%s\"}\n",
         mpfr_get_version(), MPFR_VERSION_STRING, gmp_version, __GNU_MP_VERSION,
         __GNU_MP_VERSION_MINOR, __GNU_MP_VERSION_PATCHLEVEL, __GMP_CC, __GMP_CFLAGS,
         mpd_version(), MPD_VERSION, mpfr_buildopt_tls_p(),
         mpfr_buildopt_decimal_p(), mpfr_buildopt_gmpinternals_p(), mpfr_buildopt_float128_p(),
         mpfr_buildopt_sharedcache_p(), mpfr_buildopt_tune_case(),
         EXTBENCH_CFLAGS,
#ifdef __VERSION__
         __VERSION__
#else
         "unknown"
#endif
  );
}

int main(int argc, char **argv) {
  if (argc < 2) die("usage: extbench info|reference|time ...");
  const char *mode = argv[1];
  if (strcmp(mode, "info") == 0) {
    print_info();
    return 0;
  }
  const char *inputs_path = NULL;
  const char *out_path = NULL;
  const char *cases_arg = NULL;
  int round = 0;
  Protocol proto = {3, 5000.0, 20000.0, 1, 1000000, 500000.0, 3, 20};
  for (int i = 2; i < argc; i += 2) {
    const char *arg = argv[i];
    const char *value = i + 1 < argc ? argv[i + 1] : NULL;
    if (value == NULL) die("every option takes a value");
    if (strcmp(arg, "--inputs") == 0) inputs_path = value;
    else if (strcmp(arg, "--out") == 0) out_path = value;
    else if (strcmp(arg, "--cases") == 0) cases_arg = value;
    else if (strcmp(arg, "--round") == 0) round = atoi(value);
    else if (strcmp(arg, "--warmup-iterations") == 0) proto.warmup_iterations = atoi(value);
    else if (strcmp(arg, "--warmup-time-us") == 0) proto.warmup_time_us = atof(value);
    else if (strcmp(arg, "--target-batch-us") == 0) proto.target_batch_time_us = atof(value);
    else if (strcmp(arg, "--min-batch-iterations") == 0) proto.min_batch_iterations = atoi(value);
    else if (strcmp(arg, "--max-batch-iterations") == 0) proto.max_batch_iterations = atoi(value);
    else if (strcmp(arg, "--max-sample-us") == 0) proto.max_sample_time_us = atof(value);
    else if (strcmp(arg, "--exploratory") == 0) proto.exploratory = atoi(value);
    else if (strcmp(arg, "--confirmatory") == 0) proto.confirmatory = atoi(value);
    else die("unknown option");
  }
  if (inputs_path == NULL || out_path == NULL) die("--inputs and --out are required");
  Inputs inputs;
  load_inputs(inputs_path, &inputs);

  /* Cases: the given list, or every case of the file in file order. */
  CaseId *cases = NULL;
  size_t case_count = 0;
  if (cases_arg != NULL) {
    char *copy = dup_token(cases_arg, strlen(cases_arg));
    for (char *token = strtok(copy, ","); token != NULL; token = strtok(NULL, ",")) {
      cases = realloc(cases, (case_count + 1) * sizeof(CaseId));
      cases[case_count++] = parse_case(token);
    }
    free(copy);
  } else {
    for (size_t i = 0; i < inputs.len; i++) {
      const Row *row = &inputs.rows[i];
      int seen = 0;
      for (size_t j = 0; j < case_count && !seen; j++)
        seen = strcmp(cases[j].kind, row->kind) == 0 && strcmp(cases[j].op, row->op) == 0 &&
               cases[j].size == row->size;
      if (!seen) {
        cases = realloc(cases, (case_count + 1) * sizeof(CaseId));
        snprintf(cases[case_count].kind, sizeof cases[case_count].kind, "%s", row->kind);
        snprintf(cases[case_count].op, sizeof cases[case_count].op, "%s", row->op);
        cases[case_count].size = row->size;
        case_count++;
      }
    }
  }

  FILE *out = fopen(out_path, "w");
  if (out == NULL) die("cannot open the output file");
  int timing = strcmp(mode, "time") == 0;
  if (!timing && strcmp(mode, "reference") != 0) die("mode is info, reference or time");
  for (size_t c = 0; c < case_count; c++) {
    Row **rows = NULL;
    size_t n = select_rows(&inputs, &cases[c], &rows);
    if (n == 0) die("case has no input rows");
    Prepared prepared;
    prepare(&prepared, &cases[c], rows, n);
    if (timing) time_case(out, &cases[c], &prepared, &proto, round);
    else reference_case(out, &cases[c], &prepared);
    release(&prepared);
    free(rows);
  }
  fclose(out);
  return 0;
}
