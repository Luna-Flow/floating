/*
 * Row primitives on 64-bit limbs for the native backend of the binary
 * coefficient kernel (issue 438, section 8). Each function is the C form of a
 * MoonBit function of the same name in `coeff_limbs_portable_nonjs.mbt`, which
 * stays the reference: the results are bit for bit the same.
 *
 * Rules: unsigned arithmetic only, no assembly, no `restrict` (a row keeps the
 * sequential semantics of the MoonBit loop under any overlap, except the window
 * row `luna_window_combine`, which reads four source limbs before it writes
 * four and so requires that its output does not overlap its inputs), no static data
 * but the switch below, nothing beyond <stdint.h>, <stdlib.h> and moonbit.h.
 * The 64 by 64 to 128 bit product uses `unsigned __int128` where the compiler
 * has it and four 32-bit products otherwise (tcc, 32-bit targets, MSVC `cl`
 * until its intrinsics are tested).
 *
 * The caller passes arrays and offsets in limbs; lengths are checked by the
 * MoonBit wrapper, not here.
 */
#include "moonbit.h"
#include <stdint.h>
#include <stdlib.h>
/* The assembly tier is enabled only where its code has been compiled and run (Apple arm64, clang or
 * gcc; tcc defines __GNUC__ but has no AArch64 inline assembly, so it takes the C rows);
 * -DLUNA_NO_ASM turns it off for a test build. */
#if defined(__aarch64__) && defined(__APPLE__) && (defined(__clang__) || defined(__GNUC__)) && !defined(__TINYC__) && !defined(LUNA_NO_ASM)
#define LUNA_ASM_ARM64 1
#endif
#if (defined(__x86_64__) || defined(__i386__)) && (defined(__GNUC__) || defined(__clang__)) && !defined(__TINYC__)
#include <cpuid.h>
#define LUNA_HAVE_CPUID 1
#endif

#if defined(__SIZEOF_INT128__)
__extension__ typedef unsigned __int128 luna_u128;
static inline void luna_mul64(uint64_t a, uint64_t b, uint64_t *hi, uint64_t *lo) {
  luna_u128 t = (luna_u128)a * b;
  *lo = (uint64_t)t;
  *hi = (uint64_t)(t >> 64);
}
#else
static inline void luna_mul64(uint64_t a, uint64_t b, uint64_t *hi, uint64_t *lo) {
  uint64_t al = a & 0xFFFFFFFFu, ah = a >> 32, bl = b & 0xFFFFFFFFu, bh = b >> 32;
  uint64_t ll = al * bl, lh = al * bh, hl = ah * bl, hh = ah * bh;
  uint64_t cross = (ll >> 32) + (lh & 0xFFFFFFFFu) + hl;
  *lo = (cross << 32) | (ll & 0xFFFFFFFFu);
  *hi = hh + (lh >> 32) + (cross >> 32);
}
#endif

/* 1 when the assembly tier is compiled in (arm64 Apple), 0 when the "asm" entries are the C rows */
MOONBIT_FFI_EXPORT int32_t luna_limbs_tier(void) {
#if defined(LUNA_ASM_ARM64)
  return 1;
#else
  return 0;
#endif
}

/* 1 when this build is Apple arm64 with clang or gcc, i.e. where the tier is expected to be
 * compiled in (independent of -DLUNA_NO_ASM, so that a build that lost it is visible). */
MOONBIT_FFI_EXPORT int32_t luna_limbs_expects_asm(void) {
#if defined(__aarch64__) && defined(__APPLE__) && (defined(__clang__) || defined(__GNUC__)) && !defined(__TINYC__)
  return 1;
#else
  return 0;
#endif
}

/* 1 when LUNA_FLOATING_PORTABLE (set, not "0" or empty) or LUNA_FLOATING_LIMBS is set */
MOONBIT_FFI_EXPORT int32_t luna_limbs_override_set(void) {
  const char *portable = getenv("LUNA_FLOATING_PORTABLE");
  const char *limbs = getenv("LUNA_FLOATING_LIMBS");
  if (portable != NULL && portable[0] != '\0' && !(portable[0] == '0' && portable[1] == '\0')) {
    return 1;
  }
  return limbs != NULL && limbs[0] != '\0';
}

/* Row implementation: 0 portable MoonBit loops (LUNA_FLOATING_PORTABLE set and not "0" or empty),
 * 1 C rows (LUNA_FLOATING_LIMBS=c), 2 assembly rows (the default where the tier exists, else 1) */
MOONBIT_FFI_EXPORT int32_t luna_limbs_mode(void) {
  const char *portable = getenv("LUNA_FLOATING_PORTABLE");
  if (portable != NULL && portable[0] != '\0' && !(portable[0] == '0' && portable[1] == '\0')) {
    return 0;
  }
  const char *limbs = getenv("LUNA_FLOATING_LIMBS");
  if (limbs != NULL && limbs[0] == 'c' && limbs[1] == '\0') {
    return 1;
  }
  return luna_limbs_tier() != 0 ? 2 : 1;
}

/* build information for the log of the differential test */
MOONBIT_FFI_EXPORT int32_t luna_limbs_has_int128(void) {
#if defined(__SIZEOF_INT128__)
  return 1;
#else
  return 0;
#endif
}

/* bit 0: BMI2, bit 1: ADX (x86-64 only; 0 elsewhere). Logged by the differential test
 * so that CI tells which instruction sets its runner has; no code uses them yet. */
MOONBIT_FFI_EXPORT int32_t luna_limbs_cpu_features(void) {
#if defined(LUNA_HAVE_CPUID)
  unsigned int eax = 0, ebx = 0, ecx = 0, edx = 0;
  if (__get_cpuid_count(7, 0, &eax, &ebx, &ecx, &edx)) {
    return (int32_t)((((ebx >> 8) & 1u)) | (((ebx >> 19) & 1u) << 1));
  }
#endif
  return 0;
}

/* 1 clang, 2 gcc, 3 MSVC, 4 tcc, 0 other */
MOONBIT_FFI_EXPORT int32_t luna_limbs_cc_id(void) {
#if defined(__clang__)
  return 1;
#elif defined(__GNUC__)
  return 2;
#elif defined(_MSC_VER)
  return 3;
#elif defined(__TINYC__)
  return 4;
#else
  return 0;
#endif
}

/* 1 x86-64, 2 arm64, 0 other */
MOONBIT_FFI_EXPORT int32_t luna_limbs_arch_id(void) {
#if defined(__x86_64__) || defined(_M_X64)
  return 1;
#elif defined(__aarch64__) || defined(_M_ARM64)
  return 2;
#else
  return 0;
#endif
}

/* r[0 .. n) = a[0 .. n) * b; returns the carry limb */
static uint64_t luna_row_mul_1(uint64_t *r, const uint64_t *a, int32_t n, uint64_t b) {
  uint64_t carry = 0;
  for (int32_t i = 0; i < n; i++) {
    uint64_t hi, lo;
    luna_mul64(a[i], b, &hi, &lo);
    lo += carry;
    hi += lo < carry;
    r[i] = lo;
    carry = hi;
  }
  return carry;
}

/* r[0 .. n) += a[0 .. n) * b; returns the carry limb */
static uint64_t luna_row_addmul_1(uint64_t *r, const uint64_t *a, int32_t n, uint64_t b) {
  uint64_t carry = 0;
  for (int32_t i = 0; i < n; i++) {
    uint64_t hi, lo;
    luna_mul64(a[i], b, &hi, &lo);
    lo += carry;
    hi += lo < carry;
    uint64_t sum = lo + r[i];
    hi += sum < lo;
    r[i] = sum;
    carry = hi;
  }
  return carry;
}

/* r[0 .. n) -= a[0 .. n) * b; returns the carry limb plus the borrow out of the row */
static uint64_t luna_row_submul_1(uint64_t *r, const uint64_t *a, int32_t n, uint64_t b) {
  uint64_t carry = 0;
  for (int32_t i = 0; i < n; i++) {
    uint64_t hi, lo;
    luna_mul64(a[i], b, &hi, &lo);
    lo += carry;
    hi += lo < carry;
    uint64_t current = r[i];
    uint64_t difference = current - lo;
    hi += current < lo;
    r[i] = difference;
    carry = hi;
  }
  return carry;
}

/* ---- arm64 assembly tier (Apple clang or gcc; written from the AArch64 instruction definitions) ----
 *
 * Four limbs per iteration, two separate carry chains in sequence so that each uses the one
 * flag register in turn: chain A adds the products' low words and the previous limb's high
 * words (`adds`, `adcs`, `adcs`, `adcs`, `adc` for the carry limb: the high word is at most
 * 2^64 - 2, so adding a flag cannot overflow), chain B adds (or subtracts) the destination
 * limbs. The carry of chain B of one block enters chain B of the next as the initial flag
 * (`cmp x, #1` sets C to x), so the loop-carried dependency of chain A does not wait for
 * chain B. n mod 4 limbs are done first by the C row. The macro is set only where the code
 * has been compiled and run (Apple arm64); Linux arm64 is untested and takes the C rows. */
#if defined(LUNA_ASM_ARM64)

#define LUNA_A64_LOAD "ldp x4, x5, [%[a]], #16\n ldp x6, x7, [%[a]], #16\n"
#define LUNA_A64_MUL \
  "umulh x8, x4, %[b]\n mul x4, x4, %[b]\n umulh x9, x5, %[b]\n mul x5, x5, %[b]\n" \
  "umulh x10, x6, %[b]\n mul x6, x6, %[b]\n umulh x11, x7, %[b]\n mul x7, x7, %[b]\n"
#define LUNA_A64_CHAIN_A \
  "adds x4, x4, %[ca]\n adcs x5, x5, x8\n adcs x6, x6, x9\n adcs x7, x7, x10\n adc %[ca], x11, xzr\n"
#define LUNA_A64_LOAD_R "ldp x12, x13, [%[r]]\n ldp x14, x15, [%[r], #16]\n"
#define LUNA_A64_STORE_R "stp x12, x13, [%[r]], #16\n stp x14, x15, [%[r]], #16\n"
#define LUNA_A64_STORE_S "stp x4, x5, [%[r]], #16\n stp x6, x7, [%[r]], #16\n"
#define LUNA_A64_LOOP "subs %[k], %[k], #1\n b.ne 1b\n"

/* k blocks of 4 limbs, k >= 1; ca is the carry limb in */
static uint64_t luna_a64_mul_blocks(uint64_t *r, const uint64_t *a, int64_t k, uint64_t b, uint64_t ca) {
  __asm__ volatile("1:\n" LUNA_A64_LOAD LUNA_A64_MUL LUNA_A64_CHAIN_A LUNA_A64_STORE_S LUNA_A64_LOOP
                   : [a] "+r"(a), [r] "+r"(r), [k] "+r"(k), [ca] "+r"(ca)
                   : [b] "r"(b)
                   : "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "cc", "memory");
  return ca;
}

static uint64_t luna_a64_addmul_blocks(uint64_t *r, const uint64_t *a, int64_t k, uint64_t b, uint64_t ca) {
  uint64_t cb = 0;
  __asm__ volatile("1:\n" LUNA_A64_LOAD LUNA_A64_LOAD_R LUNA_A64_MUL LUNA_A64_CHAIN_A
                   "cmp %[cb], #1\n adcs x12, x12, x4\n adcs x13, x13, x5\n adcs x14, x14, x6\n"
                   "adcs x15, x15, x7\n adc %[cb], xzr, xzr\n" LUNA_A64_STORE_R LUNA_A64_LOOP
                   : [a] "+r"(a), [r] "+r"(r), [k] "+r"(k), [ca] "+r"(ca), [cb] "+r"(cb)
                   : [b] "r"(b)
                   : "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "cc", "memory");
  return ca + cb;
}

/* returns the carry limb plus the borrow out of the row, as the C row does */
static uint64_t luna_a64_submul_blocks(uint64_t *r, const uint64_t *a, int64_t k, uint64_t b, uint64_t ca) {
  uint64_t nb = 1; /* 1: no borrow */
  __asm__ volatile("1:\n" LUNA_A64_LOAD LUNA_A64_LOAD_R LUNA_A64_MUL LUNA_A64_CHAIN_A
                   "cmp %[nb], #1\n sbcs x12, x12, x4\n sbcs x13, x13, x5\n sbcs x14, x14, x6\n"
                   "sbcs x15, x15, x7\n adc %[nb], xzr, xzr\n" LUNA_A64_STORE_R LUNA_A64_LOOP
                   : [a] "+r"(a), [r] "+r"(r), [k] "+r"(k), [ca] "+r"(ca), [nb] "+r"(nb)
                   : [b] "r"(b)
                   : "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "cc", "memory");
  return ca + 1 - nb;
}

static uint64_t luna_row_mul_1_asm(uint64_t *r, const uint64_t *a, int32_t n, uint64_t b) {
  int32_t head = n & 3;
  uint64_t carry = luna_row_mul_1(r, a, head, b);
  int64_t blocks = n >> 2;
  return blocks ? luna_a64_mul_blocks(r + head, a + head, blocks, b, carry) : carry;
}
static uint64_t luna_row_addmul_1_asm(uint64_t *r, const uint64_t *a, int32_t n, uint64_t b) {
  int32_t head = n & 3;
  uint64_t carry = luna_row_addmul_1(r, a, head, b);
  int64_t blocks = n >> 2;
  return blocks ? luna_a64_addmul_blocks(r + head, a + head, blocks, b, carry) : carry;
}
static uint64_t luna_row_submul_1_asm(uint64_t *r, const uint64_t *a, int32_t n, uint64_t b) {
  int32_t head = n & 3;
  uint64_t carry = luna_row_submul_1(r, a, head, b);
  int64_t blocks = n >> 2;
  return blocks ? luna_a64_submul_blocks(r + head, a + head, blocks, b, carry) : carry;
}
#else
/* no assembly tier here: the "asm" entry points are the C rows */
#define luna_row_mul_1_asm luna_row_mul_1
#define luna_row_addmul_1_asm luna_row_addmul_1
#define luna_row_submul_1_asm luna_row_submul_1
#endif

MOONBIT_FFI_EXPORT uint64_t luna_mul_1(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t n, uint64_t b) {
  return luna_row_mul_1(r + ro, a + ao, n, b);
}

MOONBIT_FFI_EXPORT uint64_t luna_addmul_1(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t n, uint64_t b) {
  return luna_row_addmul_1(r + ro, a + ao, n, b);
}

MOONBIT_FFI_EXPORT uint64_t luna_submul_1(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t n, uint64_t b) {
  return luna_row_submul_1(r + ro, a + ao, n, b);
}

MOONBIT_FFI_EXPORT uint64_t luna_mul_1_asm(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t n, uint64_t b) {
  return luna_row_mul_1_asm(r + ro, a + ao, n, b);
}

MOONBIT_FFI_EXPORT uint64_t luna_addmul_1_asm(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t n, uint64_t b) {
  return luna_row_addmul_1_asm(r + ro, a + ao, n, b);
}

MOONBIT_FFI_EXPORT uint64_t luna_submul_1_asm(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t n, uint64_t b) {
  return luna_row_submul_1_asm(r + ro, a + ao, n, b);
}

/* r[0 .. an + bn) = a[0 .. an) * b[0 .. bn); `r` does not overlap `a` or `b` */
typedef uint64_t (*luna_row_fn)(uint64_t *, const uint64_t *, int32_t, uint64_t);

static inline void luna_school_with(luna_row_fn mul_row, luna_row_fn addmul_row, uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t an, const uint64_t *b, int32_t bo, int32_t bn) {
  r += ro;
  a += ao;
  b += bo;
  r[bn] = mul_row(r, b, bn, a[0]);
  for (int32_t i = 1; i < an; i++) {
    r[i + bn] = addmul_row(r + i, b, bn, a[i]);
  }
}

/* r[0 .. 2 len) = s[0 .. len)^2; `r` does not overlap `s` */
MOONBIT_FFI_EXPORT void luna_school(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t an, const uint64_t *b, int32_t bo, int32_t bn) {
  luna_school_with(luna_row_mul_1, luna_row_addmul_1, r, ro, a, ao, an, b, bo, bn);
}

MOONBIT_FFI_EXPORT void luna_school_asm(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t an, const uint64_t *b, int32_t bo, int32_t bn) {
  luna_school_with(luna_row_mul_1_asm, luna_row_addmul_1_asm, r, ro, a, ao, an, b, bo, bn);
}

/* r[0 .. 2 len) = s[0 .. len)^2; `r` does not overlap `s` */
static inline void luna_sqr_school_with(luna_row_fn addmul_row, uint64_t *r, int32_t ro, const uint64_t *s, int32_t so, int32_t len) {
  r += ro;
  s += so;
  for (int32_t i = 0; i < 2 * len; i++) {
    r[i] = 0;
  }
  /* the cross products s_i * s_j, i < j, once */
  for (int32_t i = 0; i + 1 < len; i++) {
    r[i + len] = addmul_row(r + 2 * i + 1, s + i + 1, len - 1 - i, s[i]);
  }
  /* double them */
  uint64_t shifted = 0;
  for (int32_t i = 0; i < 2 * len; i++) {
    uint64_t word = r[i];
    r[i] = (word << 1) | shifted;
    shifted = word >> 63;
  }
  /* add the squares s_i * s_i at 2 i */
  uint64_t carry = 0;
  for (int32_t i = 0; i < len; i++) {
    uint64_t hi, lo;
    luna_mul64(s[i], s[i], &hi, &lo);
    uint64_t sum = r[2 * i] + lo;
    uint64_t c1 = sum < lo;
    uint64_t total = sum + carry;
    c1 += total < sum;
    r[2 * i] = total;
    uint64_t high_sum = r[2 * i + 1] + hi;
    uint64_t c2 = high_sum < hi;
    uint64_t high_total = high_sum + c1;
    c2 += high_total < high_sum;
    r[2 * i + 1] = high_total;
    carry = c2;
  }
}

MOONBIT_FFI_EXPORT void luna_sqr_school(uint64_t *r, int32_t ro, const uint64_t *s, int32_t so, int32_t len) {
  luna_sqr_school_with(luna_row_addmul_1, r, ro, s, so, len);
}

MOONBIT_FFI_EXPORT void luna_sqr_school_asm(uint64_t *r, int32_t ro, const uint64_t *s, int32_t so, int32_t len) {
  luna_sqr_school_with(luna_row_addmul_1_asm, r, ro, s, so, len);
}

/* Forced inlining of the two helpers below, so that each call of `luna_win_interior` with
 * constant flags becomes its own specialised loop. Only clang and gcc get the attribute; any
 * other compiler (MSVC `cl`, tcc) takes plain `static inline`, which compiles everywhere: without
 * inlining the specialisation is lost (the flags are tested per limb) and the results are the
 * same. */
#if defined(__clang__) || defined(__GNUC__)
#define LUNA_FORCE_INLINE static inline __attribute__((always_inline))
#else
#define LUNA_FORCE_INLINE static inline
#endif

/* ---- the window row of the wide sum (`bin_limbs_window_combine`) ----
 *
 * words[0 .. count) = x_window + (y_window ^ mask) + carry, limb by limb, where
 * the window of an operand `w` (`len` limbs) with word shift `ws` and bit shift
 * `bs` (0 <= bs < 64) has limb i = (w[i - ws] << bs) | (w[i - ws - 1] >> (64 - bs)),
 * a source limb outside 0 .. len - 1 reading as zero; mask is all ones for a
 * subtraction (x + !y + 1 - borrow_in). Returns the carry out (the borrow out
 * for a subtraction). The contract and the semantics are those of the MoonBit
 * function of the same name in `coeff_limbs_portable_nonjs.mbt`, which is the
 * reference of the differential test. `words` must not overlap `x` or `y`; `x`
 * and `y` are only read. Index arithmetic is in 64 bits (the MoonBit wrapper bounds the word
 * shifts and the lengths, see `bin_limbs_window_max`, so that the portable body's 32-bit index
 * arithmetic cannot wrap either). */
#if defined(__clang__) && defined(__has_builtin)
#if __has_builtin(__builtin_addcll)
#define LUNA_HAVE_ADDCLL 1
#endif
#endif
LUNA_FORCE_INLINE uint64_t luna_add3(uint64_t a, uint64_t b, uint64_t *carry) {
#if defined(LUNA_HAVE_ADDCLL)
  unsigned long long out;
  uint64_t sum = (uint64_t)__builtin_addcll(a, b, *carry, &out);
  *carry = out;
  return sum;
#else
  uint64_t partial = a + b;
  uint64_t c1 = partial < a;
  uint64_t sum = partial + *carry;
  c1 |= sum < partial;
  *carry = c1;
  return sum;
#endif
}

static inline uint64_t luna_win_word(const uint64_t *w, int64_t len, int64_t ws, int bs, int64_t index) {
  int64_t source = index - ws;
  uint64_t low = (source >= 0 && source < len) ? w[source] : 0;
  if (bs == 0) {
    return low;
  }
  uint64_t below = (source >= 1 && source <= len) ? w[source - 1] : 0;
  return (low << bs) | (below >> (64 - bs));
}

/* the limb of a window from the current and the previous source limb */
#define LUNA_SH(cur, prev, sh, bs, up) ((sh) ? (((cur) << (bs)) | ((prev) >> (up))) : (cur))

/* The interior of the pass, limbs `low .. high` where every source limb of both operands exists
 * (no bounds test), four limbs per iteration with one carry chain through the four sums (with
 * clang this is `adds`, `adcs`, `adcs`, `adcs`), then the remaining limbs one at a time. The
 * flags are constants at every call, so each call is its own specialised loop: `xbs`, `ybs` zero
 * means that operand is read unshifted, `use_y` zero means no second operand. */
LUNA_FORCE_INLINE void luna_win_interior(uint64_t *words, int64_t low, int64_t high, const uint64_t *x, int64_t xws, int xsh, int xbs, const uint64_t *y, int64_t yws, int ysh, int ybs, int use_y, uint64_t mask, uint64_t *carry_io) {
  uint64_t carry = *carry_io;
  int xup = 64 - xbs;
  int yup = 64 - ybs;
  uint64_t xp = xsh ? x[low - xws - 1] : 0;
  uint64_t yp = (use_y && ysh) ? y[low - yws - 1] : 0;
  int64_t i = low;
  for (; i + 4 <= high; i += 4) {
    uint64_t x0 = x[i - xws], x1 = x[i - xws + 1], x2 = x[i - xws + 2], x3 = x[i - xws + 3];
    uint64_t a0 = LUNA_SH(x0, xp, xsh, xbs, xup), a1 = LUNA_SH(x1, x0, xsh, xbs, xup);
    uint64_t a2 = LUNA_SH(x2, x1, xsh, xbs, xup), a3 = LUNA_SH(x3, x2, xsh, xbs, xup);
    xp = x3;
    uint64_t b0 = mask, b1 = mask, b2 = mask, b3 = mask;
    if (use_y) {
      uint64_t y0 = y[i - yws], y1 = y[i - yws + 1], y2 = y[i - yws + 2], y3 = y[i - yws + 3];
      b0 = LUNA_SH(y0, yp, ysh, ybs, yup) ^ mask;
      b1 = LUNA_SH(y1, y0, ysh, ybs, yup) ^ mask;
      b2 = LUNA_SH(y2, y1, ysh, ybs, yup) ^ mask;
      b3 = LUNA_SH(y3, y2, ysh, ybs, yup) ^ mask;
      yp = y3;
    }
#if defined(LUNA_HAVE_ADDCLL)
    unsigned long long c0, c1, c2, c3;
    words[i] = (uint64_t)__builtin_addcll(a0, b0, carry, &c0);
    words[i + 1] = (uint64_t)__builtin_addcll(a1, b1, c0, &c1);
    words[i + 2] = (uint64_t)__builtin_addcll(a2, b2, c1, &c2);
    words[i + 3] = (uint64_t)__builtin_addcll(a3, b3, c2, &c3);
    carry = c3;
#else
    words[i] = luna_add3(a0, b0, &carry);
    words[i + 1] = luna_add3(a1, b1, &carry);
    words[i + 2] = luna_add3(a2, b2, &carry);
    words[i + 3] = luna_add3(a3, b3, &carry);
#endif
  }
  for (; i < high; i++) {
    uint64_t xc = x[i - xws];
    uint64_t a = LUNA_SH(xc, xp, xsh, xbs, xup);
    xp = xc;
    uint64_t b = mask;
    if (use_y) {
      uint64_t yc = y[i - yws];
      b = LUNA_SH(yc, yp, ysh, ybs, yup) ^ mask;
      yp = yc;
    }
    words[i] = luna_add3(a, b, &carry);
  }
  *carry_io = carry;
}

#if defined(LUNA_ASM_ARM64)
/* ---- arm64 assembly interior of the window row ----------------------------------------------
 * Carry convention (written once): the carry is the AArch64 C flag with the add-with-carry meaning,
 * x + y + C. Before a loop `cmp c, #1` sets C to c (0 or 1); after it `adc c, xzr, xzr` reads C back.
 * A subtraction runs `sbcs` (x - y - !C), which is x + ~y + C, so C = 1 means "no borrow", the same
 * convention as the C code's `carry` (which holds 1 - borrow for a subtraction). The loop counter
 * uses `sub` and `cbnz`, which do not touch the flags, so one carry chain runs through all four
 * limbs of a block and through every block boundary. A shifted limb is (limb << bs) | (previous >> up)
 * with up = 64 - bs, written as a shift by -bs (the shift uses the low six bits); the previous limb's
 * high part stays in one register across blocks. Each loop is its own out-of-line function with seven
 * arguments, all in registers (destination, the two sources at the first limb of the first block, the
 * block count, the carry in, the two bit shifts), so the ten loops are not inlined into the head and
 * the tail of the pass and the interface costs no stack. Add or subtract and the shifted operands are
 * chosen by the caller, one function per loop. */
#define LUNA_W_LDX "ldp x0, x1, [%[px]], #16\n ldp x2, x3, [%[px]], #16\n"
#define LUNA_W_LDY "ldp x8, x9, [%[py]], #16\n ldp x10, x11, [%[py]], #16\n"
#define LUNA_W_STO "stp x0, x1, [%[po]], #16\n stp x2, x3, [%[po]], #16\n"
#define LUNA_W_LOOP "sub %[k], %[k], #1\n cbnz %[k], 1b\n"
/* x16 = 64 - xbs and x17 = 64 - ybs as shift amounts (the shift uses the low six bits, so -bs works) */
#define LUNA_W_SHX \
  "lsr x4, x0, x16\n lsl x0, x0, %[xbs]\n orr x0, x0, x7\n" \
  "lsr x5, x1, x16\n lsl x1, x1, %[xbs]\n orr x1, x1, x4\n" \
  "lsr x6, x2, x16\n lsl x2, x2, %[xbs]\n orr x2, x2, x5\n" \
  "lsr x7, x3, x16\n lsl x3, x3, %[xbs]\n orr x3, x3, x6\n"
#define LUNA_W_SHY \
  "lsr x12, x8, x17\n lsl x8, x8, %[ybs]\n orr x8, x8, x15\n" \
  "lsr x13, x9, x17\n lsl x9, x9, %[ybs]\n orr x9, x9, x12\n" \
  "lsr x14, x10, x17\n lsl x10, x10, %[ybs]\n orr x10, x10, x13\n" \
  "lsr x15, x11, x17\n lsl x11, x11, %[ybs]\n orr x11, x11, x14\n"
#define LUNA_W_CHAIN(OP) OP " x0, x0, x8\n " OP " x1, x1, x9\n " OP " x2, x2, x10\n " OP " x3, x3, x11\n"
#define LUNA_W_CHAIN0(OP) OP " x0, x0, xzr\n " OP " x1, x1, xzr\n " OP " x2, x2, xzr\n " OP " x3, x3, xzr\n"
#define LUNA_W_CLOBBER "x0","x1","x2","x3","x4","x5","x6","x7","x8","x9","x10","x11","x12","x13","x14","x15","x16","x17","cc","memory"
/* seven arguments, all in registers: destination, the two sources (at the first limb of the first block),
 * the block count, the carry limb in (0 or 1), the two bit shifts. The previous limbs of a shifted operand are
 * read from px[-1] and py[-1]. Returns the carry out. */
#define LUNA_W_FN(NAME, PRE, BODY) \
__attribute__((noinline)) static uint64_t NAME(uint64_t *po, const uint64_t *px, const uint64_t *py, int64_t k, uint64_t c, uint64_t xbs, uint64_t ybs) { \
  __asm__ volatile("neg x16, %[xbs]\n neg x17, %[ybs]\n" PRE "cmp %[c], #1\n 1:\n" BODY "adc %[c], xzr, xzr\n" \
    : [po] "+r"(po), [px] "+r"(px), [py] "+r"(py), [k] "+r"(k), [c] "+r"(c) : [xbs] "r"(xbs), [ybs] "r"(ybs) : LUNA_W_CLOBBER); \
  return c; \
}
#define PRE_X "ldur x7, [%[px], #-8]\n lsr x7, x7, x16\n"
#define PRE_Y "ldur x15, [%[py], #-8]\n lsr x15, x15, x17\n"
#define LUNA_W_ADD "adcs"
#define LUNA_W_SUB "sbcs"
LUNA_W_FN(luna_w_add_nn, "", LUNA_W_LDX LUNA_W_LDY LUNA_W_CHAIN(LUNA_W_ADD) LUNA_W_STO LUNA_W_LOOP)
LUNA_W_FN(luna_w_sub_nn, "", LUNA_W_LDX LUNA_W_LDY LUNA_W_CHAIN(LUNA_W_SUB) LUNA_W_STO LUNA_W_LOOP)
LUNA_W_FN(luna_w_add_sx, PRE_X, LUNA_W_LDX LUNA_W_SHX LUNA_W_LDY LUNA_W_CHAIN(LUNA_W_ADD) LUNA_W_STO LUNA_W_LOOP)
LUNA_W_FN(luna_w_sub_sx, PRE_X, LUNA_W_LDX LUNA_W_SHX LUNA_W_LDY LUNA_W_CHAIN(LUNA_W_SUB) LUNA_W_STO LUNA_W_LOOP)
LUNA_W_FN(luna_w_add_sy, PRE_Y, LUNA_W_LDX LUNA_W_LDY LUNA_W_SHY LUNA_W_CHAIN(LUNA_W_ADD) LUNA_W_STO LUNA_W_LOOP)
LUNA_W_FN(luna_w_sub_sy, PRE_Y, LUNA_W_LDX LUNA_W_LDY LUNA_W_SHY LUNA_W_CHAIN(LUNA_W_SUB) LUNA_W_STO LUNA_W_LOOP)
LUNA_W_FN(luna_w_add_sxy, PRE_X PRE_Y, LUNA_W_LDX LUNA_W_LDY LUNA_W_SHX LUNA_W_SHY LUNA_W_CHAIN(LUNA_W_ADD) LUNA_W_STO LUNA_W_LOOP)
LUNA_W_FN(luna_w_sub_sxy, PRE_X PRE_Y, LUNA_W_LDX LUNA_W_LDY LUNA_W_SHX LUNA_W_SHY LUNA_W_CHAIN(LUNA_W_SUB) LUNA_W_STO LUNA_W_LOOP)
LUNA_W_FN(luna_w_add_noy, "", LUNA_W_LDX LUNA_W_CHAIN0(LUNA_W_ADD) LUNA_W_STO LUNA_W_LOOP)
LUNA_W_FN(luna_w_sub_noy, "", LUNA_W_LDX LUNA_W_CHAIN0(LUNA_W_SUB) LUNA_W_STO LUNA_W_LOOP)
LUNA_W_FN(luna_w_add_noy_sx, PRE_X, LUNA_W_LDX LUNA_W_SHX LUNA_W_CHAIN0(LUNA_W_ADD) LUNA_W_STO LUNA_W_LOOP)
LUNA_W_FN(luna_w_sub_noy_sx, PRE_X, LUNA_W_LDX LUNA_W_SHX LUNA_W_CHAIN0(LUNA_W_SUB) LUNA_W_STO LUNA_W_LOOP)

/* The interior of the pass in assembly: whole blocks of four limbs, then the remaining zero to three
 * limbs through the C interior with constant flags, as the C body does (a call with run-time flags
 * would keep every branch). */
static void luna_win_interior_asm(uint64_t *words, int64_t low, int64_t high, const uint64_t *x, int64_t xws, int xsh, int xbs, const uint64_t *y, int64_t yws, int ysh, int ybs, int use_y, uint64_t mask, uint64_t *carry_io) {
  int64_t blocks = (high - low) >> 2;
  if (blocks > 0) {
    const uint64_t *px = x + (low - xws);
    const uint64_t *py = use_y ? y + (low - yws) : x;
    uint64_t c = *carry_io, sub = mask != 0;
    uint64_t *po = words + low;
    if (!use_y) {
      if (!xsh) c = sub ? luna_w_sub_noy(po, px, py, blocks, c, xbs, ybs) : luna_w_add_noy(po, px, py, blocks, c, xbs, ybs);
      else c = sub ? luna_w_sub_noy_sx(po, px, py, blocks, c, xbs, ybs) : luna_w_add_noy_sx(po, px, py, blocks, c, xbs, ybs);
    } else if (!xsh && !ysh) c = sub ? luna_w_sub_nn(po, px, py, blocks, c, xbs, ybs) : luna_w_add_nn(po, px, py, blocks, c, xbs, ybs);
    else if (xsh && !ysh) c = sub ? luna_w_sub_sx(po, px, py, blocks, c, xbs, ybs) : luna_w_add_sx(po, px, py, blocks, c, xbs, ybs);
    else if (!xsh && ysh) c = sub ? luna_w_sub_sy(po, px, py, blocks, c, xbs, ybs) : luna_w_add_sy(po, px, py, blocks, c, xbs, ybs);
    else c = sub ? luna_w_sub_sxy(po, px, py, blocks, c, xbs, ybs) : luna_w_add_sxy(po, px, py, blocks, c, xbs, ybs);
    *carry_io = c;
    low += 4 * blocks;
  }
  if (low < high) {
    if (!use_y) {
      if (!xsh) luna_win_interior(words, low, high, x, xws, 0, 0, y, yws, 0, 0, 0, mask, carry_io);
      else luna_win_interior(words, low, high, x, xws, 1, xbs, y, yws, 0, 0, 0, mask, carry_io);
    } else if (!xsh && !ysh) luna_win_interior(words, low, high, x, xws, 0, 0, y, yws, 0, 0, 1, mask, carry_io);
    else if (!xsh) luna_win_interior(words, low, high, x, xws, 0, 0, y, yws, 1, ybs, 1, mask, carry_io);
    else if (!ysh) luna_win_interior(words, low, high, x, xws, 1, xbs, y, yws, 0, 0, 1, mask, carry_io);
    else luna_win_interior(words, low, high, x, xws, 1, xbs, y, yws, 1, ybs, 1, mask, carry_io);
  }
}
#endif

LUNA_FORCE_INLINE uint64_t luna_window_combine_impl(int use_asm, uint64_t *words, int32_t count, const uint64_t *x, int32_t x_len, int32_t x_ws, int32_t x_bs, const uint64_t *y, int32_t y_len, int32_t y_ws, int32_t y_bs, int32_t subtract, uint64_t carry_in) {
  (void)use_asm;
  uint64_t mask = subtract ? ~(uint64_t)0 : 0;
  uint64_t carry = subtract ? 1 - carry_in : carry_in;
  int use_y = y_len > 0;
  int64_t low = (int64_t)x_ws + 1;
  int64_t high = (int64_t)x_ws + x_len;
  if (use_y) {
    int64_t ylow = (int64_t)y_ws + 1;
    int64_t yhigh = (int64_t)y_ws + y_len;
    low = low > ylow ? low : ylow;
    high = high < yhigh ? high : yhigh;
  }
  if (low > count) low = count;
  if (low < 0) low = 0;
  if (high > count) high = count;
  if (high < low) high = low;
  for (int64_t i = 0; i < low; i++) {
    uint64_t a = luna_win_word(x, x_len, x_ws, x_bs, i);
    uint64_t b = luna_win_word(y, y_len, y_ws, y_bs, i) ^ mask;
    words[i] = luna_add3(a, b, &carry);
  }
  if (low < high) {
#if defined(LUNA_ASM_ARM64)
    if (use_asm) {
      luna_win_interior_asm(words, low, high, x, x_ws, x_bs != 0, x_bs, y, y_ws, use_y && y_bs != 0, y_bs, use_y, mask, &carry);
    } else
#endif
    if (!use_y) {
      if (x_bs == 0) {
        luna_win_interior(words, low, high, x, x_ws, 0, 0, y, y_ws, 0, 0, 0, mask, &carry);
      } else {
        luna_win_interior(words, low, high, x, x_ws, 1, x_bs, y, y_ws, 0, 0, 0, mask, &carry);
      }
    } else if (x_bs == 0 && y_bs == 0) {
      luna_win_interior(words, low, high, x, x_ws, 0, 0, y, y_ws, 0, 0, 1, mask, &carry);
    } else if (x_bs == 0) {
      luna_win_interior(words, low, high, x, x_ws, 0, 0, y, y_ws, 1, y_bs, 1, mask, &carry);
    } else if (y_bs == 0) {
      luna_win_interior(words, low, high, x, x_ws, 1, x_bs, y, y_ws, 0, 0, 1, mask, &carry);
    } else {
      luna_win_interior(words, low, high, x, x_ws, 1, x_bs, y, y_ws, 1, y_bs, 1, mask, &carry);
    }
  }
  for (int64_t i = high; i < count; i++) {
    uint64_t a = luna_win_word(x, x_len, x_ws, x_bs, i);
    uint64_t b = luna_win_word(y, y_len, y_ws, y_bs, i) ^ mask;
    words[i] = luna_add3(a, b, &carry);
  }
  return subtract ? 1 - carry : carry;
}

MOONBIT_FFI_EXPORT uint64_t luna_window_combine(uint64_t *words, int32_t count, const uint64_t *x, int32_t x_len, int32_t x_ws, int32_t x_bs, const uint64_t *y, int32_t y_len, int32_t y_ws, int32_t y_bs, int32_t subtract, uint64_t carry_in) {
  return luna_window_combine_impl(0, words, count, x, x_len, x_ws, x_bs, y, y_len, y_ws, y_bs, subtract, carry_in);
}

/* the same pass with the assembly interior where the tier exists, else the C body */
MOONBIT_FFI_EXPORT uint64_t luna_window_combine_asm(uint64_t *words, int32_t count, const uint64_t *x, int32_t x_len, int32_t x_ws, int32_t x_bs, const uint64_t *y, int32_t y_len, int32_t y_ws, int32_t y_bs, int32_t subtract, uint64_t carry_in) {
  return luna_window_combine_impl(1, words, count, x, x_len, x_ws, x_bs, y, y_len, y_ws, y_bs, subtract, carry_in);
}
