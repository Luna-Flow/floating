# 数値意味論

この文書は `0.7.0` 文書で共有する語彙を定義し、数学的値、保存表現、rounding
status、checked failure、interval enclosure を区別します。

## 値と表現

有限 binary 値は signed non-negative coefficient と 2 のべきの積、有限 decimal
値は signed non-negative coefficient と 10 のべきの積です。異なる表現が同じ
数学的値を表すことがあります。

Decimal の `12.3400`、`12.340`、`12.34` は同じ数値ですが cohort が異なります。
保存 exponent が quantum です。Parsing は quantum を保持し、`normalized()` または
`reduce_ctx()` は数学的値を変えずに末尾 zero を除いて exponent を調整できます。

Precision は representation metadata と rounding bound であり、全 digit の有意性を
証明しません。`with_precision` は round する場合がありますが、radix の変更や
binary/decimal conversion は行いません。

## Rounding と context

共有 binary-style rounding は nearest-even、toward-zero、toward-positive、
toward-negative、away-from-zero です。Decimal は half-up、half-down、zero-five-up
などの GDA mode も持ちます。

`BinaryContext`、`DecimalContext`、`BallContext` は bounded-format policy を
explicit にします。Domain に応じて precision、exponent bound、clamp、rounding、
tininess detection を持ち、`binary64`、`decimal64` などの preset が標準境界を与えます。

次のいずれかが観測可能なら context API を使います。

- exact rounding direction
- overflow、underflow、subnormal、inexact、rounded status
- before/after-rounding tininess
- decimal clamp または exponent cohort rule
- fixed interchange format

## Flags、status、trap、error

Operation flag は定義済み結果を生成したときの condition で、automatic exception
ではありません。Accumulated IEEE status が必要なら step ごとの flags を combine します。

GDA は三つの関連値を区別します。

- `raised`: 現在の operation が生成した condition
- `status`: thread 済み operation の sticky union
- `traps`: `Completed` を `Trapped` に変える enabled condition

Trapped `GdaOutcome` も GDA-defined result、next context、raised flags を保持します。
複数 enabled signal が同時に raised された場合は固定 precedence で trap を選びます。

`ArithmeticError` は異なり、checked capability が要求された scalar result を
生成できないことを表します。Binary/interval result wrapper はこの error を
short-circuit します。Decimal composition は native state を保ち、`DecimalChecked`
は defined result と IEEE flags を蓄積し、`GdaDecimalChecked` は defined result を
失わず sticky status を thread して trap で short-circuit します。

## Scalar の特殊値

Binary/decimal scalar は対応範囲に応じて signed zero、positive/negative infinity、
quiet/signaling NaN を公開します。NaN payload と signaling state は representation
data であり、arithmetic は signaling NaN を quiet にして invalid condition を
raise する場合があります。

Numeric equality と representation equality は同一ではありません。

- signed zero は数値的に equal でも sign が異なります。
- Decimal cohort member は equal でも `same_quantum` が false の場合があります。
- NaN は通常 comparison で unordered です。
- total comparison は sorting/protocol 用に NaN と cohort を含む表現を順序付けます。

Formatted text から推測せず、classification と explicit total-order API を使います。

## Interval 意味論

`BallFloat` は binary endpoint で囲まれた実数集合です。Arithmetic result は各 input
set から値を選んだ全数学的結果を含む必要があり、outward rounding が inclusion
invariant を守ります。

主要 state は次の通りです。

- **Empty**: 実数を含みません。
- **Entire**: 全実数を含みます。
- **非空 bounded/unbounded interval**: endpoint 間の値を含みます。
- **NaI**: Empty と異なる decorated invalid interval です。

Containment、subset、overlap、disjointness、definite comparison が scalar total
order を置き換えます。Zero を含む interval による division は Entire を返しても
正しく、conservative enclosure は tight でなくても successful value です。

Decoration は continuity/domain condition の強さを記録し、scalar flag でも
`BallFloatResult` の保存値でもありません。

## Conversion と projection

ある radix の有限値が別 radix で有限とは限らないため、binary-to-decimal と
decimal-to-binary は rounding を必要とする場合があります。Conversion が contract
の一部なら precision と rounding を explicit に選びます。

Interchange conversion は任意精度 conversion より狭く、binary16/32/64/128 と
decimal32/64/128 は固定 field width、exponent bound、special encoding、status
behavior を強制します。

`semantic` projection は保持する数学的値には exact ですが、representation metadata
を意図的に失います。Cross-package comparison/diagnostic には使えますが、quantum、
payload、signed zero、decoration、flags の round-trip には使いません。

## 判断 checklist

API を選ぶ前に次を確認します。

1. 必要な結果は scalar value、representation、real set のどれか。
2. radix、precision、exponent bound、quantum を観測する必要があるか。
3. per-operation flags、sticky GDA status、checked short-circuit error のどれが必要か。
4. NaN、infinity、signed zero、Empty、Entire、NaI が発生するか。
5. partial comparison で十分か、total order/set relation が必要か。
6. conversion は arbitrary precision か fixed interchange か。
7. どの finite conformance matrix が behavior claim を裏付けるか。
