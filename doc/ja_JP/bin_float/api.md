# @bin_float.BinFloat

## 安定性

`BinFloat`、`BinCoeff`、binary context/flags、binary16/32/64/128
interchange は `0.5.0` の application API です。limb layout、algorithm threshold、
IEEE 754 全体は安定契約ではありません。

この文書は `0.5.0` API を説明します。数学・テスト境界は
[適合性](./conformance.md) にあります。

## Context、flag、interchange

- `BinaryRoundingMode`：nearest-even、nearest-away、toward-zero、toward-positive、
  toward-negative、away-from-zero。
- `TininessDetection`：before/after rounding。
- `BinaryContext::new`、`try_new`、`unbounded`、`binary16`、`binary32`、`binary64`、`binary128`。
- `BinaryFlags`：5 つの IEEE flag、`combine`、`to_testfloat_bits`。
- `BinaryInterchangeFormat`、`BinaryInterchange::from_hex`、`to_hex`、
  `to_bin_float`、`from_bin_float`、`BinFloat::to_interchange`。

encode API は `(bits, flags)` を返します。

## Constructor と観測

`BinFloat::make`、`zero`、`negative_zero`、`one`、`inf`、`nan`、`quiet_nan`、
`signaling_nan`、`from_int`、`from_coefficient`、`from_float`、`from_double` を使えます。

公開係数型は非負の `BinCoeff` です。`BinCoeff::from_uint64`、`parse`、
`from_bytes_be` で構築し、符号は独立した `negative?` 引数で指定します。
二進/ball API は `BigInt` の境界を公開しません（Decimal と Semantic の既存
`BigInt` API は変更されません）。

`BinCoeff` は `zero`、`one`、`from_uint64`、`parse`、byte 変換、比較、bit
query、加算、`sub_checked`、乗算、平方、`div_rem_checked`、`gcd`、自然数冪、
shift、bitwise operation を公開します。非負型なので、負の結果になり得る減算と
ゼロ除算になり得る除算は checked API です。

### 0.4 からの移行

| 旧 API | 現在の API |
| --- | --- |
| `BinFloat::from_bigint(n)` | `BinFloat::from_coefficient(c, negative=...)` |
| `BinFloat::make(n, e, p)` | `BinFloat::make(c, e, p, negative=...)` |
| `value.significand()` | `value.coefficient()` |
| `BinaryInterchange::from_bits(n, format)` / `bits() -> BigInt` | `from_bits(c, format)` / `bits() -> BinCoeff` |
| `BallFloat::from_bigint(n)` | `BallFloat::from_coefficient(c, negative=...)` |
| checked `from_bigint(n)` | checked `from_coefficient(c, negative=...)` |
| `NatHomomorphism` / `IntegralHomomorphism` | 二進型から削除、明示的 constructor を使用 |

`classify`、`precision`、`sign`、`is_negative`、`is_negative_zero`、
`is_quiet_nan`、`is_signaling_nan`、`nan_payload`、`coefficient`、`exponent2`、
`is_zero`、`normalized`、`with_precision`、`ulp`、`compare`、`min`、`max`、`clamp`、`clamp_checked`
が観測・通常操作を提供します。NaN は順序比較できません。

## 算術

通常の `+`、`-`、`*`、`/` と `add`、`sub`、`mul`、`div` は無界 nearest-even
context を使い、flag を返しません。IEEE 意味論には `round_ctx`、`add_ctx`、
`sub_ctx`、`mul_ctx`、`div_ctx`、`sqrt_ctx`、`pow_int_ctx` を使い、
`(BinFloat, BinaryFlags)` を受け取ります。

従来の checked helper は `sqrt_bounds_for_precision`、`sqrt_for_precision`、
`compare_checked`、`div_checked`、`sqrt`、`pow_int` です。
## 表現

有限値は独立符号、`BinCoeff`、`exponent2`、precision で表され、零・無限大・NaN は観測可能です。

## Access、正規化、比較

`coefficient`、`exponent2`、`normalized`、`compare` と classification predicate を使います。NaN は通常の全順序に入りません。

## 算術と変換

通常演算は任意精度、context 演算は value と flags、interchange は fixed-width bit encoding を返します。

## Checked 算術 API

checked trait は `ArithmeticError` を明示的に返し、flags は `*_ctx` の責務です。

## Trait 面

`Floating`、checked capability、標準 operator trait を最小の組合せとして公開します。
