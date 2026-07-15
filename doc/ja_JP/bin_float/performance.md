# `bin_float` Performance

<!-- historical-performance-baseline: 0.6.1 -->

## Contract

performance threshold、limb layout、NTT prime、scratch storage、fallback selection は実装詳細です。algorithm/target が異なっても public result、flags、interchange bits は完全に同一でなければなりません。

## 表現

non-JS target は inline 64/128-bit coefficient と little-endian 32-bit limb を使い、JavaScript は hidden host `bigint` adapter を使います。public `BinCoeff` により backend choice は観測できません。

## 乗算

balanced multiplication は 96 limb 未満で schoolbook、その後 Karatsuba、Toom-3、transform bound を満たす二素数 Montgomery NTT + CRT を選びます。unbalanced input は block multiplication または overlap-add を使います。native/LLVM の現在値は Toom-3/NTT multiply が 2,048 limb、NTT square が 768、Wasm/Wasm-GC は 4,096 と 3,072 です。native の square dispatch は 512 limb で specialized schoolbook から recursive multiplication へ切り替え、他 target は従来の 768-limb 境界を維持します。

## 除算・平方根・GCD

division は one-limb path、48 divisor limb 未満の Knuth、48 以上の Burnikel–Ziegler、1,024 以上の Newton reciprocal を使います。square root は 512 bit まで fixed-width kernel、それ以上は divide-and-conquer、large GCD は Lehmer batching です。

## 測定

統一 `bench/bin_float` Maremark harness は balanced block で係数 kernel、数値 core、checked 全経路、意味的に等価な square 候補を比較します。auto-tune は versioned per-scale policy を出力し、threshold は計測した target だけへ適用します。全 target correctness test は引き続き必須です。

elementary release gate は immutable `0.6.1` commit と dirty candidate tree を
別々に archive し、同一 add/mul/div/sqrt workload を注入して、53/128/512 bit の
alternating AB/BA native pair を十組収集します。candidate が 3% 以上遅く、かつ
Maremark 95% bootstrap interval の下限が正の場合だけ release を阻止します。
`0.7.0` で初めて追加された function は candidate workload として測定し、この
release を最初の正当な baseline とします。`0.6.1` に存在しない API の timing を
捏造しません。

## Trade-off

schoolbook は setup/allocation を抑え、recursive algorithm は漸近 work を減らし、NTT は transform と temporary storage の代わりに非常に大きい balanced input を改善します。全 fast path に exact fallback があり、dispatch は semantics を変更しません。
