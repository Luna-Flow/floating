/*
 * Row primitives on 64-bit limbs for the native backend of the binary
 * coefficient kernel (issue 438, section 8). Each function is the C form of a
 * MoonBit function of the same name in `coeff_limbs_portable_nonjs.mbt`, which
 * stays the reference: the results are bit for bit the same.
 *
 * Rules: unsigned arithmetic only, no assembly, no `restrict` (a row keeps the
 * sequential semantics of the MoonBit loop under any overlap), no static data
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
/* The assembly tier is enabled only where its code has been compiled and run (Apple arm64);
 * -DLUNA_NO_ASM turns it off for a test build. */
#if defined(__aarch64__) && defined(__APPLE__) && (defined(__clang__) || defined(__GNUC__)) && !defined(LUNA_NO_ASM)
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
#if defined(__aarch64__) && defined(__APPLE__) && (defined(__clang__) || defined(__GNUC__))
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
