#define main mpfr_binary_oracle_main
#include "generate_mpfr_elementary_oracle.c"
#undef main

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
  for (size_t operation_index = 0; operation_index < operation_count;
       ++operation_index) {
    for (long case_index = 0; case_index < cases_per_operation; ++case_index) {
      long integer = 0;
      make_operands(operations[operation_index].name, left, right, &integer,
                    &state);
      evaluate(operations[operation_index].name, lower, left, right, integer,
               MPFR_RNDD);
      evaluate(operations[operation_index].name, upper, left, right, integer,
               MPFR_RNDU);
      printf("%s ", operations[operation_index].name);
      print_hex(left);
      fputc(' ', stdout);
      if (operations[operation_index].arity == 2) {
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
