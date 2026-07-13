set shell := ["sh", "-eu", "-c"]

default:
    just --list

fmt:
    @sh tools/run_moon_clean_exec.sh fmt

update:
    sh tools/run_moon_clean_exec.sh update
    awk ' \
      $1 == "import" && $2 == "{" { in_import = 1; next } \
      in_import && $1 == "}" { in_import = 0; next } \
      in_import { \
        gsub(/[",]/, "", $1); \
        sub(/@.*/, "", $1); \
        if ($1 != "") print $1; \
      } \
    ' moon.mod | while IFS= read -r dep; do \
      sh tools/run_moon_clean_exec.sh add --upgrade --no-update "$dep"; \
    done
    sh tools/run_moon_clean_exec.sh build

build:
    @sh tools/run_moon_clean_exec.sh build

docs:
    @python3 tools/doc_quality.py
    @sh tools/run_moon_clean_exec.sh test src/doc_examples --target native --deny-warn

# Run the fast pull-request gate.
pr jobs='':
    @python3 tools/run_ci.py quick {{ jobs }}

smoke *args:
    @python3 tools/conformance.py smoke --backend decimal_gda {{ args }}

plan *args:
    @python3 tools/conformance.py plan --backend decimal_gda {{ args }}

fetch corpus='official':
    @python3 tools/conformance.py fetch --backend decimal_gda {{ corpus }}

conformance action backend='decimal_gda' *args:
    @python3 tools/conformance.py {{ action }} --backend {{ backend }} {{ args }}

# Run only the IEEE 754 Decimal conformance suite.
decimal-ci jobs='':
    @python3 tools/run_ci.py decimal {{ jobs }}

# Run only the General Decimal Arithmetic compatibility suite.
decimal-gda-ci jobs='':
    @python3 tools/run_ci.py decimal_gda {{ jobs }}

# Run the independent IEEE 754 decimal32/64/128 corpus on supported targets.
ieee-ci:
    @python3 tools/conformance.py run --backend decimal --run-target native --run-target wasm --run-target wasm-gc --run-target js

ieee-vectors family='mandatory-decimal' count='100000' output='.tmp/ieee-{{ family }}.jsonl':
    @mkdir -p .tmp
    @python3 tools/generate_ieee_decimal_vectors.py --family {{ family }} --count {{ count }} --output {{ output }}

# Run the authoritative binary conformance suite.
bin-ci jobs='':
    @python3 tools/run_ci.py bin {{ jobs }}

# Run the authoritative interval conformance suite.
interval-ci jobs='':
    @python3 tools/run_ci.py interval {{ jobs }}

# Run all checks, tests, and authoritative suites.
ci jobs='':
    @python3 tools/run_ci.py all {{ jobs }}

decimal-kernel-ci:
    @sh tools/run_moon_clean_exec.sh test src/decimal/coeff_kernel_wbtest.mbt --no-parallelize

bin-kernel-ci:
    @sh tools/run_moon_clean_exec.sh test src/bin_float --target all --no-parallelize

bin-bench target='native':
    @python3 tools/run_bin_coeff_bench.py --target {{ target }}

decimal-threshold-bench *args:
    @python3 tools/run_decimal_threshold_bench.py {{ args }}

tree:
    sh tools/run_moon_clean_exec.sh tree

publish:
    sh tools/run_moon_clean_exec.sh package --frozen
