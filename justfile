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

pr *args:
    sh tools/run_moon_clean_exec.sh check --target all
    sh tools/run_moon_clean_exec.sh info
    python3 tools/run_dectest_interpreter.py {{ args }}

smoke *args:
    @sh tools/run_moon_clean_exec.sh run src/gda_expr_cli -- {{ args }} testdata/decimal/smoke.decTest

plan *args:
    @python3 tools/run_dectest_interpreter.py --plan {{ args }}

fetch corpus='official':
    @python3 tools/fetch_decimal_corpora.py {{ corpus }}

ci:
    @sh tools/run_moon_clean_exec.sh test src/decimal/coeff_kernel_wbtest.mbt --no-parallelize

tree:
    sh tools/run_moon_clean_exec.sh tree

publish:
    sh tools/run_moon_clean_exec.sh package --frozen
