# testdata

The corpora and expected values that the gates and the differential harness
read. Nothing in a published package depends on this directory: the library zip
holds `library/` only, and the tables compiled into its white-box tests are
generated MoonBit source (see [`tools/README.md`](../tools/README.md)).

| Directory | What it is | Tracked or fetched | Used by |
| --- | --- | --- | --- |
| [`bin_float/`](./bin_float/README.md) | pinned MPFR 4.2.2 witnesses (elementary functions, decimal output, `strtofr`), the random-differential rows and their regressions, and `smoke/` TestFloat vectors with a manifest | tracked; the full Berkeley TestFloat and SoftFloat corpora and the MPFR sources are fetched into `.tmp/binfloat-conformance/` (`tools/fetch_binfloat_corpora.py`, pins in `corpora.json`) | `just gate binary`, `just conformance ... binary`, `just random-diff` |
| [`decimal/`](./decimal/README.md) | IEEE 754-2019 decimal vectors: interchange (DPD and BID), static oracle examples, the totalOrder corpus, an excerpt of the decTest data, rows for the pi-inverse functions, and the seeded MPFR rows for the elementary functions (`random/`) | tracked | `just gate decimal` (`tools/run_ieee_decimal.py`), `just random-diff` |
| [`decimal_gda/`](./decimal_gda/README.md) | General Decimal Arithmetic: the smoke file, the staged interpreter plan and the seeded libmpdec rows (`random/`) | tracked; the official `dectest.zip` and `dectest0.zip` and their unpacked `official/` and `official0/` are fetched (`tools/fetch_decimal_corpora.py`, pins in `corpora.json`) and git-ignored | `just gate decimal_gda`, `just conformance ... decimal_gda`, `just random-diff` |
| [`interval/`](./interval/README.md) | IEEE 1788 interval rows: a smoke `.itl` file and the staged interpreter plan | tracked; the ITF1788 corpus is fetched (`tools/fetch_interval_corpora.py`, pinned revision in `corpora.json`) into `itf1788/` and git-ignored | `just gate interval`, `just conformance ... interval` |
| `elementary/` | `performance_baseline.json` (the pinned baseline commit and the paired-measurement protocol of the immutable baseline gate) and `capability_matrix.json` (the elementary-function families per standard for release 0.8.0; no gate reads it) | tracked | `just gate elementary` (`tools/run_elementary_performance_gate.py`) |
| `context_vectors.txt` | 69 boundary contexts of `bin_float`, IEEE `decimal` and `decimal_gda` with their verdict (legal or not), the one list the Python rules (`tools/context_rules.py`) and the library constructors (`tooling/src/consistency/context_vectors_wbtest.mbt`) are both tested against | tracked | `tools/context_rules_test.py`, the consistency tests of `tooling` |
| `external_baseline/` | `summary-0.11.0.json` and `summary-0.10.2.json`, the stored measurements of floating against MPFR and libmpdec for the two releases (schema v1; the quick check divides by the medians of the latest), `summary.md`, the tables of 0.11.0, and, from 0.12, one `summary-<version>-<configuration>.json` (schema v2), one `samples-<version>-<configuration>.json.gz` (the pairs every number is computed from) and one `summary-<configuration>.md` per release and configuration of the floating side | tracked (`just bench external publish --version V`) | `just bench external quick`, `compare`, `recompute` and `page` |

Fetched data is verified by SHA-256 against the pins in each `corpora.json`; the
nightly workflow caches it. A fresh worktree fetches it on first use. `testdata/**/stress/`
and `testdata/**/*.jsonl` are scratch output and git-ignored. The gates are
described in the [verification page](../doc/manual/verification.md) and the
[architecture page](../doc/manual/architecture.md).
