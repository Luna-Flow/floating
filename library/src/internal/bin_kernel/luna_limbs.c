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

/* 1 when the C rows are used, 0 when LUNA_FLOATING_PORTABLE is set (and not "0" or empty) */
MOONBIT_FFI_EXPORT int32_t luna_limbs_enabled(void) {
  const char *value = getenv("LUNA_FLOATING_PORTABLE");
  if (value == NULL || value[0] == '\0' || (value[0] == '0' && value[1] == '\0')) {
    return 1;
  }
  return 0;
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

MOONBIT_FFI_EXPORT uint64_t luna_mul_1(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t n, uint64_t b) {
  return luna_row_mul_1(r + ro, a + ao, n, b);
}

MOONBIT_FFI_EXPORT uint64_t luna_addmul_1(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t n, uint64_t b) {
  return luna_row_addmul_1(r + ro, a + ao, n, b);
}

MOONBIT_FFI_EXPORT uint64_t luna_submul_1(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t n, uint64_t b) {
  return luna_row_submul_1(r + ro, a + ao, n, b);
}

/* r[0 .. an + bn) = a[0 .. an) * b[0 .. bn); `r` does not overlap `a` or `b` */
MOONBIT_FFI_EXPORT void luna_school(uint64_t *r, int32_t ro, const uint64_t *a, int32_t ao, int32_t an, const uint64_t *b, int32_t bo, int32_t bn) {
  r += ro;
  a += ao;
  b += bo;
  r[bn] = luna_row_mul_1(r, b, bn, a[0]);
  for (int32_t i = 1; i < an; i++) {
    r[i + bn] = luna_row_addmul_1(r + i, b, bn, a[i]);
  }
}

/* r[0 .. 2 len) = s[0 .. len)^2; `r` does not overlap `s` */
MOONBIT_FFI_EXPORT void luna_sqr_school(uint64_t *r, int32_t ro, const uint64_t *s, int32_t so, int32_t len) {
  r += ro;
  s += so;
  for (int32_t i = 0; i < 2 * len; i++) {
    r[i] = 0;
  }
  /* the cross products s_i * s_j, i < j, once */
  for (int32_t i = 0; i + 1 < len; i++) {
    r[i + len] = luna_row_addmul_1(r + 2 * i + 1, s + i + 1, len - 1 - i, s[i]);
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
