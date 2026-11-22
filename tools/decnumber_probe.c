/* Probe of decNumber 3.68 built with DECSUBSET=1, the oracle of the subset (extended=0) rows of the decimal_gda tests.
 *
 * Reads one row per line from standard input, fields separated by a vertical bar:
 *   op|rounding|x|y|precision|emin|emax|clamp|extended
 * op: add subtract multiply divide divideint remainder remainderNear power quantize rescale plus minus abs compare
 *     max min maxmag minmag exp ln log10 sqrt tointegral nextplus nextminus nexttoward; y is ignored by a unary op; rounding is a decNumber
 *     name without the DEC_ROUND_ prefix (HALF_EVEN, DOWN, UP, CEILING, FLOOR, HALF_UP, HALF_DOWN, 05UP).
 * Writes: the result as decNumberToString, a vertical bar and 13 flag letters (see the end of main).
 * Pin: decNumber 3.68, https://speleotrove.com/decimal/decNumber-icu-368.zip, sha256
 *   14ec2cf30b58758493a7661b78b80abfb281652b61a425b85cda83173518fe25 (ICU licence; the same pin as the header of
 *   testdata/decimal_gda/deviations.tsv). The archive is fetched by the user, checked against that sha256, unpacked
 *   into an empty directory outside the repository and never committed.
 * Build against the unpacked sources (<src> is the directory that holds decNumber.c; DECSUBSET=1 compiles the
 * subset arithmetic of GDA 1.70, which the rows with extended=0 need):
 *   cc -O1 -DDECSUBSET=1 -DDECNUMDIGITS=100 -I<src> tools/decnumber_probe.c \
 *      <src>/decNumber.c <src>/decContext.c -o <out>/decnumber_probe
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "decNumber.h"

static enum rounding rounding_of(const char *s) {
  static const struct { const char *n; enum rounding r; } t[] = {
    {"HALF_EVEN", DEC_ROUND_HALF_EVEN}, {"HALF_UP", DEC_ROUND_HALF_UP}, {"HALF_DOWN", DEC_ROUND_HALF_DOWN},
    {"DOWN", DEC_ROUND_DOWN}, {"UP", DEC_ROUND_UP}, {"CEILING", DEC_ROUND_CEILING},
    {"FLOOR", DEC_ROUND_FLOOR}, {"05UP", DEC_ROUND_05UP}};
  for (size_t i = 0; i < sizeof t / sizeof t[0]; i++) if (!strcmp(t[i].n, s)) return t[i].r;
  fprintf(stderr, "bad rounding %s\n", s); exit(2);
}

int main(void) {
  char line[4096];
  while (fgets(line, sizeof line, stdin)) {
    char *f[9]; int n = 0; char *p = line;
    line[strcspn(line, "\r\n")] = 0;
    if (!line[0]) continue;
    f[n++] = p;
    while (n < 9 && (p = strchr(p, '|'))) { *p++ = 0; f[n++] = p; }
    if (n != 9) { fprintf(stderr, "bad row %s\n", line); return 2; }
    decContext c;
    decContextDefault(&c, DEC_INIT_BASE);
    c.digits = atoi(f[4]); c.emin = atoi(f[5]); c.emax = atoi(f[6]);
    c.clamp = (uint8_t)atoi(f[7]); c.extended = (uint8_t)atoi(f[8]);
    c.round = rounding_of(f[1]); c.traps = 0;
    decNumber x, y, r;
    /* the operands are read exactly: a wide context of its own, so that neither the precision nor the exponent
       range of the operation touches them (the library reads its operands without a context as well) */
    decContext w;
    decContextDefault(&w, DEC_INIT_BASE);
    w.digits = DECNUMDIGITS; w.emin = -999999999; w.emax = 999999999; w.extended = c.extended; w.traps = 0;
    decNumberFromString(&x, f[2], &w);
    decNumberFromString(&y, f[3], &w);
    c.status = 0;
    const char *op = f[0];
    if (!strcmp(op, "add")) decNumberAdd(&r, &x, &y, &c);
    else if (!strcmp(op, "subtract")) decNumberSubtract(&r, &x, &y, &c);
    else if (!strcmp(op, "multiply")) decNumberMultiply(&r, &x, &y, &c);
    else if (!strcmp(op, "divide")) decNumberDivide(&r, &x, &y, &c);
    else if (!strcmp(op, "divideint")) decNumberDivideInteger(&r, &x, &y, &c);
    else if (!strcmp(op, "remainder")) decNumberRemainder(&r, &x, &y, &c);
    else if (!strcmp(op, "remainderNear")) decNumberRemainderNear(&r, &x, &y, &c);
    else if (!strcmp(op, "power")) decNumberPower(&r, &x, &y, &c);
    else if (!strcmp(op, "quantize")) decNumberQuantize(&r, &x, &y, &c);
    else if (!strcmp(op, "rescale")) decNumberRescale(&r, &x, &y, &c);
    else if (!strcmp(op, "nextplus")) decNumberNextPlus(&r, &x, &c);
    else if (!strcmp(op, "nextminus")) decNumberNextMinus(&r, &x, &c);
    else if (!strcmp(op, "nexttoward")) decNumberNextToward(&r, &x, &y, &c);
    else if (!strcmp(op, "plus")) decNumberPlus(&r, &x, &c);
    else if (!strcmp(op, "minus")) decNumberMinus(&r, &x, &c);
    else if (!strcmp(op, "abs")) decNumberAbs(&r, &x, &c);
    else if (!strcmp(op, "compare")) decNumberCompare(&r, &x, &y, &c);
    else if (!strcmp(op, "max")) decNumberMax(&r, &x, &y, &c);
    else if (!strcmp(op, "min")) decNumberMin(&r, &x, &y, &c);
    else if (!strcmp(op, "maxmag")) decNumberMaxMag(&r, &x, &y, &c);
    else if (!strcmp(op, "minmag")) decNumberMinMag(&r, &x, &y, &c);
    else if (!strcmp(op, "exp")) decNumberExp(&r, &x, &c);
    else if (!strcmp(op, "ln")) decNumberLn(&r, &x, &c);
    else if (!strcmp(op, "log10")) decNumberLog10(&r, &x, &c);
    else if (!strcmp(op, "sqrt")) decNumberSquareRoot(&r, &x, &c);
    else if (!strcmp(op, "tointegral")) decNumberToIntegralValue(&r, &x, &c);
    else { fprintf(stderr, "bad op %s\n", op); return 2; }
    char *buf = malloc(1000);
    decNumberToString(&r, buf);
    printf("%s|", buf);
    free(buf);
    /* flag letters: inexact, rounded, invalid operation, division by zero, overflow, underflow, subnormal,
       clamped, division impossible, division undefined, invalid context, lost digits (subset), conversion syntax; a dash where the flag is clear */
    static const struct { uint32_t m; char l; } fl[] = {
      {DEC_Inexact, 'x'}, {DEC_Rounded, 'r'}, {DEC_Invalid_operation, 'i'}, {DEC_Division_by_zero, 'z'},
      {DEC_Overflow, 'o'}, {DEC_Underflow, 'u'}, {DEC_Subnormal, 's'}, {DEC_Clamped, 'c'},
      {DEC_Division_impossible, 'd'}, {DEC_Division_undefined, 'U'}, {DEC_Invalid_context, 'C'},
      {DEC_Lost_digits, 'L'}, {DEC_Conversion_syntax, 'S'}};
    for (size_t i = 0; i < sizeof fl / sizeof fl[0]; i++) putchar((c.status & fl[i].m) ? fl[i].l : '-');
    putchar('\n');
  }
  return 0;
}
