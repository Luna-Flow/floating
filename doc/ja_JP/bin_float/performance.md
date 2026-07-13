# `bin_float` Performance

## Contract

performance threshold、limb layout、NTT prime、scratch storage、fallback selection は実装詳細です。algorithm/target が異なっても public result、flags、interchange bits は完全に同一でなければなりません。

## 表現

non-JS target は inline 64/128-bit coefficient と little-endian 32-bit limb を使い、JavaScript は hidden host `bigint` adapter を使います。public `BinCoeff` により backend choice は観測できません。

## 乗算

balanced multiplication は 96 limb 未満で schoolbook、その後 Karatsuba、Toom-3、transform bound を満たす二素数 Montgomery NTT + CRT を選びます。unbalanced input は block multiplication または overlap-add を使います。native/LLVM の現在値は Toom-3/NTT multiply が 2,048 limb、NTT square が 768、Wasm/Wasm-GC は 4,096 と 3,072 です。

## 除算・平方根・GCD

division は one-limb path、48 divisor limb 未満の Knuth、48 以上の Burnikel–Ziegler、1,024 以上の Newton reciprocal を使います。square root は 512 bit まで fixed-width kernel、それ以上は divide-and-conquer、large GCD は Lehmer batching です。

## 測定

skip された white-box bench は crossover 周辺で各 algorithm を強制し、dense、sparse、square、unbalanced shape を比較します。threshold 変更には全 target differential correctness test と再現可能な release-mode measurement が必要で、単一 machine の結果を portable constant にはしません。

## Trade-off

schoolbook は setup/allocation を抑え、recursive algorithm は漸近 work を減らし、NTT は transform と temporary storage の代わりに非常に大きい balanced input を改善します。全 fast path に exact fallback があり、dispatch は semantics を変更しません。
