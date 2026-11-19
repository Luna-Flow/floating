set shell := ["sh", "-eu", "-c"]

default:
    just --list

fmt:
    @sh tools/run_moon_clean_exec.sh fmt

# Refresh the registry, then upgrade the dependencies of both workspace modules
# (the library and `tooling`; the library itself is a workspace member, not a
# registry dependency of `tooling`).
update:
    sh tools/run_moon_clean_exec.sh update
    for manifest in moon.mod tooling/moon.mod; do \
      directory=$(dirname "$manifest"); \
      awk ' \
        $1 == "import" && $2 == "{" { in_import = 1; next } \
        in_import && $1 == "}" { in_import = 0; next } \
        in_import { \
          gsub(/[",]/, "", $1); \
          sub(/@.*/, "", $1); \
          if ($1 != "" && $1 != "Luna-Flow/floating") print $1; \
        } \
      ' "$manifest" | while IFS= read -r dep; do \
        sh tools/run_moon_clean_exec.sh -C "$directory" add --upgrade --no-update "$dep"; \
      done; \
    done
    sh tools/run_moon_clean_exec.sh build

build:
    @sh tools/run_moon_clean_exec.sh build

# Check doc/manual (tools/doc_quality.py) and run the documentation examples.
docs:
    @python3 tools/run_docs.py

gate scope jobs='':
    @python3 tools/run_ci.py {{ scope }} {{ jobs }}

# Run the fast pull-request gate.
pr jobs='':
    @just gate quick {{ jobs }}

conformance action backend *args:
    @python3 tools/conformance.py {{ action }} --backend {{ backend }} {{ args }}

# Seeded random differential testing against MPFR and libmpdec through the
# mare_mark harness. Actions: run, replay, minimize, smoke, plan. Examples:
#   just random-diff run --count 1000000 --target native --target wasm
#   just random-diff replay 20261118.add.1234 --target native
#   just random-diff smoke
random-diff action *args:
    @python3 tools/random_differential.py {{ action }} {{ args }}

ieee-vectors family='mandatory-decimal' count='100000' output='.tmp/ieee-{{ family }}.jsonl':
    @mkdir -p .tmp
    @python3 tools/generate_ieee_decimal_vectors.py --family {{ family }} --count {{ count }} --output {{ output }}

# Run all checks, tests, and authoritative suites.
ci jobs='':
    @just gate all {{ jobs }}

decimal-kernel-ci:
    @sh tools/run_moon_clean_exec.sh test src/internal/decimal_kernel --no-parallelize

bin-kernel-ci:
    @sh tools/run_moon_clean_exec.sh test src/bin_float --target all --no-parallelize

# Run a Maremark suite, or `just bench external run` for floating against MPFR and libmpdec.
bench suite *args:
    @python3 tools/benchmark.py {{ suite }} {{ args }}

tree:
    sh tools/run_moon_clean_exec.sh tree

publish:
    sh tools/run_moon_clean_exec.sh package --frozen
