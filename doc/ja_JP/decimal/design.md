# `decimal` 設計

## 責務と表現

`decimal` は任意精度 10 進値、General Decimal Arithmetic の context/flags、
decimal32/64/128 interchange を担当します。有限値は独立した符号、係数、10 進
指数、cohort、精度を持ち、負の零、無限大、qNaN/sNaN、payload も観測可能です。

係数 kernel は非公開実装です。little-endian base-1e9 の `UInt` limb と、広い中間
値用の `UInt64` を使います。1 limb の係数は inline 表現、大きな値は limb 配列に
格納し、零は一つの canonical 表現、配列には先頭零がなく、10 進桁数は正確です。
公開 API はこの layout を公開しません。BigInt は公開変換/serialization と test
oracle/debug 境界だけに残し、Decimal の hot path は係数を直接処理します。

解析と quantum-sensitive 操作は末尾零/cohort を保持できます。`normalized()`/
`reduce_ctx()` は数学値を変えずに除去可能な 10 の冪だけを取り除くため、数値の
equality と `compare_total` は異なる関係です。

## 係数と丸め algorithm

小さな処理は inline arithmetic、checked 加減算、Comba/schoolbook 乗算、専用 square、
single-limb 除算、正確な冪、GCD、整数 `sqrt_rem`、平方による冪乗を使います。疎な
operand は非零項を圧縮し、短辺が十分に大きい強い不均衡 shape は balanced block
に分割し、小さい shape では単一の正規化 accumulator を使います。

平衡乗算の分岐は長さ、density、比率、square 形状、target-specific threshold を
同時に考慮します。production の順序は schoolbook、Karatsuba、Toom-3、二つの法を
使う NTT convolution です。Karatsuba/Toom-3 は深さを制限した scratch を使い、Toom-3
の負の中間値は内部 signed scratch にだけ存在し、補間の exact division を検査します。
NTT は小さな 10 進 working digit、CRT reconstruction、長さ/係数上限の検査を持ち、
条件を満たさない場合は fallback します。

除算は word division、正規化した Knuth Algorithm D、Burnikel–Ziegler の block 再帰、
Newton reciprocal の順に選択します。各経路は quotient/remainder の不変条件を検証し、
安全な algorithm へ fallback できます。scratch arena は一時 limb buffer を再利用しますが、
rewind 後の buffer が結果へ逃げることはありません。

Context 操作は特殊値、正確な係数/指数、8 種の decimal rounding、指数境界/subnormal/
clamp、`DecimalFlags` の順に処理します。FMA は加算まで積を正確に保ち、sqrt と初等
関数は係数 native の guard digit と反復/級数 refinement の後に一度だけ context finalize
します。quantize は目標指数を固定し、係数が context に収まらなければ `invalid_operation`
を報告します。

## Context と interchange 境界

`DecimalContext` は明示的な input、`*_ctx` は `(Decimal, DecimalFlags)` を返します。
flags は明示的に蓄積され、ambient mutable state は使いません。`DecimalInterchange`
は DPD と BID の decimal32/64/128 に同じ Decimal semantic layer を使い、canonicalization、
non-canonical finite encoding、NaN payload、Infinity、signed zero を共通に処理します。
encoding の違いで arithmetic や rounding を複製しません。

## 能力と適合性の境界

算術、FMA、整数除算/余り、quantize/rescale、total comparison、logical digit、隣接値、
分類、formatting、interchange、初等関数を提供します。GDA と IEEE gate は別々に計測し、
固定 `official`/`official0` corpus は合法な scalar semantics、独立した IEEE decimal32/64/128
vectors は操作、flags、特殊値、total order、format conversion、DPD/BID bit pattern を
検証します。対応する target では双方とも failed/unsupported をゼロにします。

## 計算量と権威参考

`n` 個の base-1e9 limb では加減算、比較、shift、正規化、single-limb 除算は `O(n)`、
schoolbook と Knuth 除算は `O(n²)` です。Karatsuba、Toom-3、NTT、Burnikel–Ziegler、
Newton は実測 crossover が setup cost を正当化する場合だけ選択します。各 algorithm の
出口で canonicalize と正確な carry 検査を行い、最適化が Decimal rounding や cohort の
意味を変えないようにします。

参考文献は Knuth, *The Art of Computer Programming*, Vol. 2 (Algorithm D)、Karatsuba
乗算、Bodrato の Toom-Cook 補間、Burnikel–Ziegler, *Fast Recursive Division*、
Brent–Zimmermann, *Modern Computer Arithmetic*、Cowlishaw の GDA specification と
decNumber、IEEE 754-2019 / ISO 60559 です。

## Evidence Map

[IEEE conformance](./conformance.md)、[`decimal_gda` conformance](../decimal_gda/conformance.md)、[performance](./performance.md) は別々の evidence ledger です。GDA status、IEEE flags、benchmark threshold を混同しません。
