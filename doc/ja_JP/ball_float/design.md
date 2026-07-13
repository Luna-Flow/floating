# `ball_float` 設計

## 責務と表現

実際の保存形式は外向き丸めを施した `lo_`、`hi_` と precision です。`new(center, radius)` は構築ビューであり、保存フィールドではありません。非空区間は `lo <= hi` で NaN 端点を持たず、Empty/Entire/装飾 NaI を区別します。

## Algorithm 選択

加減算は単調な端点式、乗算は四つの端点積の min/max、除算は零を含まない分母なら逆数端点を使います。零を内包する分母は片側なら半無限、内部交差なら Entire にします。`BallContext` は下端を負方向、上端を正方向へ丸め、`inexact`/`overflow`/`underflow` を返します。

初等関数は `BinCoeff` 上の有向 dyadic 区間証明を使います。各演算を有限の作業精度で外向きに丸め、打ち切った級数は明示的な剰余界で包絡します。exp/ln は縮約と級数、sin/cos は共有した Machin の π 包絡、象限縮約、交代級数、臨界点検出、tan は極の検出、正底冪は `exp(exponent*ln(base))` です。証明できない場合は sin/cos が `[-1,1]`、tan が Entire に戻り、包絡を優先します。

## Decoration と relation

装飾は最小 grade を伝播し、関係は集合関係であって全順序ではありません。ITF1788 の strict gate は `testdata/interval/README.md` の全 phase（general-power と trigonometric を含む）を対象にし、reverse 操作は範囲外です。

## 能力境界

固定 corpus は 4,113/4,113 を strict pass し unsupported はゼロです。安全な
fallback は inclusion を保証しますが、常に representable な最小幅とは限りません。

## 包含不変条件と certificate

入力 `X=[x_lo,x_hi]` に対し、加算の下端は負方向、上端は正方向へ丸めます。
乗除算は全端点候補の極値を選び、tight bound を証明できなければ安全な enclosure
へ広げます。Empty、Entire、decorated NaI は別の状態です。

range reduction、series、明示的 remainder bound が初等関数の enclosure を証明し、
極値や pole を跨ぐ場合は critical point を調べます。証明不足なら sin/cos は
`[-1,1]`、tan は Entire に fallback します。strict baseline は general-power と
trigonometric を含みますが reverse operation は未対応です。

## 計算量と trade-off

基本 interval は定数回の endpoint 演算なので precision `p` で `O(M(p))`、
storage は二 endpoint です。初等関数は `O(k)` series 項と `O(p)` working
precision を使います。Entire/`[-1,1]` fallback は tightness より inclusion を
優先する選択です。

## Inclusion invariant

すべての constructor と operation は必要なら外向きに広げ、tightness より set inclusion を先に保証します。

## Evidence Map

耐久的な algorithm contract は本書、固定された有限 claim と対象外は [Conformance](./conformance.md) に記録します。binary coefficient crossover evidence は [`bin_float` performance](../bin_float/performance.md) が所有し、`ball_float` は同 kernel を再実装せず利用します。
