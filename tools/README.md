# tools

The scripts of the repository: the gates, the corpus fetchers, the generators of
expected values and white-box tables, the oracle programs written in C, the
checks that no compiler enforces and the benchmark drivers. They are Python 3
without third-party packages (the C programs need GMP, MPFR and libmpdec), and each
has a `*_test.py` next to it; `just pr` runs the tests (`TEST: Python tooling`).
Nothing here is part of a published package.

Run them from the repository root, normally through `just`.

## Gates and orchestration

| Script | Purpose |
| --- | --- |
| `run_ci.py`, `ci_schedule.py` | `just gate <scope>` and `just pr`: the stages, their lanes and the scheduler |
| `run_docs.py` | `just docs`: the manual's quality checks and examples |
| `conformance.py`, `conformance_runtime.py`, `conformance_ui.py`, `conformance_cli.py`, `corpus_common.py` | `just conformance <action> <backend>`: fetch, plan, run and report one conformance backend; builds the `floating-conformance` executable |
| `run_binfloat_interpreter.py`, `run_dectest_interpreter.py`, `run_itl_interpreter.py`, `run_ieee_decimal.py` | the staged interpreters for TestFloat and MPFR, GDA decTest, ITF1788 and the IEEE decimal corpus |
| `random_differential.py`, `random_differential_minimize.py` | `just random-diff`: seeded campaigns against MPFR and libmpdec, replay and minimization |
| `run_moon_clean_exec.sh` | runs `moon` with a clean lock state and a chosen target directory |

## Checks

| Script | Purpose |
| --- | --- |
| `run_python_tests.py` | the Python tooling tests (`TEST: Python tooling`) with a guard: it fails if a test writes into `library/`, `tooling/`, `doc/` or `testdata/` of the checkout, however briefly |
| `generated_paths.py` | the one list of the throwaway sources that gate stages write into the source trees (the manual examples, the IEEE smoke); shared by the package check and the Python test guard |
| `check_imports.py` | package independence, the library's dependencies, equal versions and identical `LICENSE` files |
| `check_package_contents.py` | the shape of the zip of each module (`just publish`) |
| `doc_quality.py`, `check_doc_examples.py`, `conformance_checklist.py` | the manual: sections, links, versions, API snapshots, runnable examples, the generated checklist |
| `native_test_timing.py` | which native test files are slowest |

## Corpus fetchers

`fetch_binfloat_corpora.py`, `fetch_decimal_corpora.py` and `fetch_interval_corpora.py`
download the pinned corpora of [`testdata/`](../testdata/README.md) and verify their
SHA-256.

## Generators of expected values and tables

| Script | Produces |
| --- | --- |
| `generate_mpfr_random_oracle.c`, `generate_mpfr_elementary_oracle.c`, `generate_mpfr_pow_oracle.c`, `generate_mpfr_decimal_string_oracle.c`, `generate_mpfr_decimal_interval_oracle.c`, `mpfr_decimal_enclosure.c` | MPFR 4.2.2 oracle rows (C programs) |
| `generate_mpfr_decimal_random.py`, `generate_libmpdec_random.py`, `generate_decimal_elementary_oracle.py`, `range_boundary_rows.py`, `decimal_oracles.py` | seeded and range-boundary rows for the decimal and binary cores |
| `generate_ieee_decimal_vectors.py`, `generate_decimal_total_order.py` | IEEE decimal vectors and the totalOrder corpus |
| `generate_decimal_atan2pi_scaled_rows.py`, `generate_decimal_exp_range_rows.py`, `generate_decimal_pi_inverse_rows.py`, `generate_decimal_pm1_rows.py`, `generate_decimal_rcp_rows.py`, `generate_decimal_to_bin_rows.py`, `decimal_row_table.py` | the MoonBit tables compiled into the white-box tests of `library/src/decimal` |
| `mpfr_sqrt_ternary_repro.c`, `mpfr_sqrt_ternary_search.c` | the standalone reproducer and search for the MPFR `sqrt` ternary-value bug |

## Benchmarks

| Script | Purpose |
| --- | --- |
| `benchmark.py` | `just bench <suite>`: the Maremark suites of `tooling/src/bench` and the external baseline |
| `external_baseline.py`, `external_baseline.c` | floating against MPFR and libmpdec on the same operands (`just bench external ...`) |
| `external_stats.py` | pure statistics of the external baseline: paired net times, bootstrap intervals, the verdict on the net ratio |
| `run_elementary_performance_gate.py`, `run_gda_benchmark.py`, `decimal_dispatch_model.py`, `fixtures/` | the immutable baseline gate, the quick GDA benchmark and the dispatch calibration model, with the white-box fixtures they inject |
