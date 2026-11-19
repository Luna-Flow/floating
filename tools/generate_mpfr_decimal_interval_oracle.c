#define main mpfr_binary_oracle_main
#include "generate_mpfr_elementary_oracle.c"
#undef main

static const operation_spec decimal_operations[] = {
    {"exp2m1", 1}, {"exp10m1", 1}, {"log2p1", 1}, {"log10p1", 1},
};

int main(int argc, char **argv) {
  long cases_per_operation = 4;
  uint64_t seed = UINT64_C(20260715);
  if (argc >= 2)
    cases_per_operation = parse_positive(argv[1], "cases-per-operation");
  if (argc >= 3) seed = (uint64_t)parse_positive(argv[2], "seed");
  if (argc > 3) {
    fprintf(stderr, "usage: %s [cases-per-operation] [seed]\n", argv[0]);
    return 2;
  }
  printf("# mpfr-decimal-interval-v1 mpfr=%s work-precision=768 seed=%llu\n",
         mpfr_get_version(), (unsigned long long)seed);
  puts("# operation left right integer lower upper exact");
  mpfr_t left;
  mpfr_t right;
  mpfr_t lower;
  mpfr_t upper;
  mpfr_init2(left, 512);
  mpfr_init2(right, 512);
  mpfr_init2(lower, 768);
  mpfr_init2(upper, 768);
  uint64_t state = seed;
  size_t operation_count = sizeof(operations) / sizeof(operations[0]);
  size_t extra_count = sizeof(decimal_operations) / sizeof(decimal_operations[0]);
  /* The decimal-only IEEE 754-2019 9.2 functions (#236) follow the shared
     table and continue its random sequence, so the rows of the shared table
     are unchanged; each has `2 * cases_per_operation` cases. */
  for (size_t index = 0; index < operation_count + extra_count; ++index) {
    const operation_spec *operation =
        index < operation_count ? &operations[index]
                                : &decimal_operations[index - operation_count];
    long cases = index < operation_count ? cases_per_operation
                                         : 2 * cases_per_operation;
    for (long case_index = 0; case_index < cases; ++case_index) {
      long integer = 0;
      make_operands(operation->name, left, right, &integer, &state);
      evaluate(operation->name, lower, left, right, integer, MPFR_RNDD);
      evaluate(operation->name, upper, left, right, integer, MPFR_RNDU);
      printf("%s ", operation->name);
      print_hex(left);
      fputc(' ', stdout);
      if (operation->arity == 2) {
        print_hex(right);
      } else {
        fputc('-', stdout);
      }
      printf(" %ld ", integer);
      print_hex(lower);
      fputc(' ', stdout);
      print_hex(upper);
      printf(" %d\n", mpfr_equal_p(lower, upper) != 0);
    }
  }
  mpfr_clear(upper);
  mpfr_clear(lower);
  mpfr_clear(right);
  mpfr_clear(left);
  return 0;
}
