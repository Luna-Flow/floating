# `decimal` Performance

## Baseline Gate

`tools/run_decimal_bench.py` compares the current tree with the immutable manifest in `testdata/decimal/performance_baseline.json`. It runs paired AB/BA/AB processes, requires at least nine accepted samples per cell, rejects unstable MAD, and fails a paired median regression above 5%.

## Operand Model

Measurements separate limb count from dense, sparse, square, and unbalanced shapes. The kernel stores canonical little-endian base-1e9 limbs, while NTT converts to smaller working digits. One global digit threshold cannot describe padding or shape crossovers.

## Native Multiplication Calibration

Native uses schoolbook→Karatsuba at 96 limbs for multiply and 48 for square, Karatsuba→Toom-3 at 1,152, and transform-band NTT thresholds. Multiply bands begin at 1,728/2,816/4,608/7,680 limbs; square bands begin at 640/1,040/1,824/3,648/7,296. Other targets retain conservative independent values.

## Division Calibration

Native Burnikel–Ziegler thresholds are 2,816, 5,120, and 10,240 limbs for increasing block bands. Newton reciprocal division remains implemented for differential tests but is not automatically selected on native because the measured path is slower than Burnikel–Ziegler.

## Statistical Method

Threshold experiments use ABBA or BAAB order, rotate size order between processes, reject unstable processes, fit weighted non-increasing isotonic regression, and bootstrap complete process columns. Production boundaries require a 95% upper confidence threshold, a one-sided sign test at `p <= 0.05`, and at least 3% median improvement.

## Reproduction And Interpretation

```sh
python3 tools/run_decimal_bench.py --target native
python3 tools/run_decimal_threshold_bench.py --model --transition mul-toom3-ntt-32k \
  --model-low 4096 --model-high 5120 --model-step 128 \
  --processes 5 --samples 9 --bootstrap-samples 5000
```

Thresholds are target-specific evidence, not API promises. Correctness is always established by coefficient differential tests and IEEE/GDA conformance before a faster path is accepted.
