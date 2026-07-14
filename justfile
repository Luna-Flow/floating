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
    @python3 tools/run_docs.py

gate scope jobs='':
    @python3 tools/run_ci.py {{ scope }} {{ jobs }}

# Run the fast pull-request gate.
pr jobs='':
    @just gate quick {{ jobs }}

conformance action backend *args:
    @python3 tools/conformance.py {{ action }} --backend {{ backend }} {{ args }}

ieee-vectors family='mandatory-decimal' count='100000' output='.tmp/ieee-{{ family }}.jsonl':
    @mkdir -p .tmp
    @python3 tools/generate_ieee_decimal_vectors.py --family {{ family }} --count {{ count }} --output {{ output }}

# Run all checks, tests, and authoritative suites.
ci jobs='':
    @just gate all {{ jobs }}

decimal-kernel-ci:
    @sh tools/run_moon_clean_exec.sh test src/decimal/coeff_kernel_wbtest.mbt --no-parallelize

bin-kernel-ci:
    @sh tools/run_moon_clean_exec.sh test src/bin_float --target all --no-parallelize

bench suite *args:
    @python3 tools/benchmark.py {{ suite }} {{ args }}

tree:
    sh tools/run_moon_clean_exec.sh tree

publish:
    sh tools/run_moon_clean_exec.sh package --frozen
