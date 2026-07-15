# `bin_float` 設計

`bin_float` は 0.7.0 の binary core で、arbitrary-precision dyadic exact semantics と
`BinaryContext` 下の declared IEEE 754-2019 behavior を両立します。Public name は
`src/bin_float/pkg.generated.mbti`、limb layout/threshold/scratch は private detail です。

## Design Contract

`BinCoeff` は exact non-negative integer arithmetic、`BinFloat` は dyadic/special state、
`BinaryContext` は operation ごとの precision/exponent/rounding/tininess/flags を担当します。
Kernel choice は exact coefficient の cost だけを変え、floating result は finalization のみが決めます。

## Representation / Invariant

Finite value は `(-1)^negative × coefficient × 2^exponent2`。Normalization 後の nonzero
coefficient は odd で、sign は独立するため signed zero を保持します。Infinity、qNaN、sNaN、
payload は有限モデル外の明示 state です。

Non-JS は inline 64/128-bit または little-endian 32-bit limbs、JS は同一 API の背後で host
`bigint` を使用します。Caller は storage/algorithm selection を観測できません。

## Standard Alignment

IEEE path は special classification → exact dyadic/rational または certified enclosure → target
direction へ一回 rounding → exponent/tininess → value + `BinaryFlags`。`BinaryInterchange` は
binary16/32/64/128 を host Float/Double 経由なしで扱います。

Pinned TestFloat matrix は四 format の add/sub/mul/div/sqrt、五 rounding direction、二 tininess
policy、MPFR 4.2.2 は documented sqrt/integer-power/elementary boundary を覆います。有限 matrix
の pass は全 IEEE operation/input の claim ではありません。

## Coefficient Algorithm Selection

Multiplication は shorter limb `n`、longer `m`、target、proof precondition で選択します。

| Decision | Condition | Path | 理由 |
| --- | --- | --- | --- |
| small | `n < 96` | inline/schoolbook | setup/allocation を回避 |
| transform | target NTT threshold かつ CRT bounds | two-prime Montgomery NTT + CRT | large dense product |
| oversized | full transform 不可、overlap 可 | overlap-add NTT | transform scaling を維持 |
| unbalanced | transform check 後 `m > 2n` | longer operand block | rectangular padding を回避 |
| large balanced | Toom-3 threshold | Toom-3 | recursive product 数を削減 |
| medium | otherwise | scratch Karatsuba | transform より低い setup |

| Target | Karatsuba | Toom-3 / NTT mul | NTT square | recursive square |
| --- | ---: | ---: | ---: | ---: |
| native | 96 | 2,048 | 768 | 512 |
| LLVM | 96 | 2,048 | 768 | 768 |
| Wasm / Wasm-GC | 96 | 4,096 | 3,072 | 768 |

Square は dedicated schoolbook path。NTT は transform/reconstruction bounds を検査し、失敗時は
exact fallback。Division は inline/word、48 未満 Knuth、48 以上 BZ、1,024 以上 Newton、
near-equal short quotient には bounded high-product search。全 path は `n=qd+r`、`0<=r<d`。
Sqrt は 512 bits まで fixed-width、それ以上 divide-and-conquer、GCD は Euclid→Lehmer です。

## Certified Elementary Functions

`try_*_ctx` は directed lower/upper enclosure を target context で丸め、value と flags が一致した
時だけ採用します。最大 12 refinement、増分 `max(32, work/2)`。Range reduction/rounding cell
が証明できない場合 structured `CertificationFailure`。Non-try API も同じ proof path です。

## Optimization / Boundary Tuning

Maremark は balanced/unbalanced/sparse/dense/square と target を分けて測定します。Candidate は
cutoff 前・点・後の exact differential/property test と paired benchmark benefit の両方が必要。
Tuning は private dispatch boundary を動かせますが numerical contract は動かせません。

## Complexity / Trade-off

Schoolbook `O(n^2)`、Karatsuba `O(n^log2(3))`、Toom-3 `O(n^log3(5))`、NTT 約
`O(n log n)`。Large BZ/Newton division は multiplication cost に近づきます。実装は exactness
制約下で expected cost を最適化し、speed のため exactness を弱めません。

## Evidence Map

- [API](./api.md)：0.7.0 public surface
- [Tutorial](./tutorial.md)：construction/context workflow
- [Conformance](./conformance.md)：TestFloat/MPFR claim
- [Performance](./performance.md)：target dispatch と immutable release comparison baseline
