# `decimal` 設計

`decimal` は 0.7.1 の IEEE-oriented arbitrary-precision decimal core です。Quantum-preserving
value、explicit context/flags、decimal32/64/128 interchange、certified elementary を提供します。
[`decimal_gda`](../decimal_gda/design.md) は独立 GDA sticky/trap model で、型は alias ではありません。

## Design Contract

Coefficient kernel は exact integer facts のみを計算し、shared finalization が bounded decimal
result を決定します：classification → exact sign/coefficient/preferred exponent → one rounding →
exponent/subnormal/tininess/clamp → value + flags。Kernel optimization は quantum/signed zero/NaN/
flags を変えません。

## Representation / Cohort

Finite value は `(-1)^negative × coefficient × 10^exponent10`。`1.2300` (quantum -4) と
`1.23` (-2) は同じ数値でも別 cohort です。Precision に収まる parse は input exponent を保持し、
`normalized/reduce_ctx` の明示呼出だけが 10 の factor を除きます。

Private `DecCoeff` は small inline または canonical little-endian base-`10^9` limbs + exact digit
count。`BigInt` は public conversion/serialization と oracle boundary に限定します。

## IEEE 754 Alignment

IEEE context/preset は precision、rounding、exponent、clamp、tininess を明示し、`*_ctx` は tuple
を返します。FMA は exact product を aligned addition まで保持し一回 rounding。
`DecimalInterchange` は DPD/BID と signed zero/infinity/qNaN/sNaN/payload を扱います。
GDA sticky/trap behavior は `decimal_gda` の責務です。

## Coefficient Algorithm Selection

Selector は limb count、density、balance、square、transform length、target を使用し、dense balanced
は schoolbook/Comba→Karatsuba→Toom-3→dual-modulus NTT、sparse/unbalanced は専用 path です。

| Target | Karatsuba mul/square | Toom-3 | first NTT mul/square | BZ | Newton |
| --- | ---: | ---: | ---: | ---: | ---: |
| native | 96 / 48 | 1,152 | 1,728 / 640 | adaptive 2,816+ | disabled |
| LLVM | 96 / 96 | 2,048 | 4,096 / 2,048 | 2,048 | 4,096 |
| Wasm / Wasm-GC / JS | 96 / 96 | 4,096 | 8,192 / 4,096 | 2,048 | 4,096 |

Native NTT mul は 1,728/2,816/4,608/7,680/8,192、square は
640/1,040/1,824/3,648/7,296/8,192 の piecewise boundary。BZ は 2,816→5,120→10,240。
Native Newton は実装・test 済みでも measurement が production crossover を支持しないため disabled。

Toom exact division、NTT bounds/CRT、division identity を検査し、失敗は exact fallback。Scratch
buffer は返却 value に escape しません。

## Rounding、Exponent、Quantum

Finalization は guard/sticky から overflow/underflow/subnormal/rounded/inexact/clamped を決めます。
`quantize` は target exponent を固定し、fit 不可なら invalid-operation。Parse は quantum を保持し、
`from_string_ctx` はさらに exponent policy と flags を返します。

## Certified Elementary Functions

Decimal input を downward/upward dyadic interval に変換し `ball_float` で評価、endpoint を exact
integer arithmetic で Decimal へ戻し、value/flags が一致した場合のみ採用します。Initial work は
最低 128 bits、12-step budget。MPFR 4.2.2 768-bit oracle は 29 operations、3 formats、8 rounding
modes の 2,784 rows、libmpdec `allcr=1` は GDA-compatible subset を独立検査します。

## Optimization / Boundary Tuning

Maremark は dense/sparse/balanced/unbalanced/square/kernel/full context を分離し order を回転します。
Production path は exact differential test と practical benefit の両方が必要。Precision/exponent/
rounding/quantum は semantic boundary、limb cutoff は private dispatch boundary です。

## Complexity / Trade-off

Add/compare/normalize/shift/word-div は `O(n)`、schoolbook/Knuth は quadratic。Karatsuba/Toom/NTT/
BZ/Newton は setup/storage/precondition と引換えに large cost を削減し、measured crossover まで
simple algorithm を維持します。

## 0.7.1 Semantic Preservation Proof

Exact decimal division path は coefficient GCD を除去し、reduced denominator が `2^i * 5^j` のときだけ採用します。
Exact coefficient と preferred exponent を作った後、generic route と同じ finalizer を呼びます。Bounded inexact path も
bound が unique result を証明できない場合は fallback します。したがって allocation と division work は減っても、
quantum、rounding、overflow/underflow、flags は変わりません。

受入条件は IEEE observation tuple（class、sign、coefficient、exponent、precision、flags、interchange value）の一致です。
固定 IEEE corpus、four-target public API matrix、division/remainder regression、exact-path differential test が release evidence を構成し、
threshold は private performance policy のままです。

## Evidence Map

[API](./api.md)、[Tutorial](./tutorial.md)、[IEEE Conformance](./conformance.md)、
[Performance](./performance.md)、独立した [`decimal_gda` Conformance](../decimal_gda/conformance.md)
を参照してください。
