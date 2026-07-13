# @decimal.Decimal

## 安定性

`Decimal`、`DecimalContext`、`DecimalFlags`、decimal interchange は
`0.6.0` の application API です。内部 `DecCoeff` layout は公開面ではなく、固定
合法 GDA corpus は完全適合です。除外は `#` placeholder/non-scalar の不正入力だけです。

このページは `0.6.0` IEEE API と分離された GDA 表現を説明します。

## 表現

## 使用前の注意

`Decimal` は decimal semantics を表しますが、すべての operation が exact だとは限りません。flags や exponent boundary が必要なら `DecimalContext` を明示します。

## 意味論の注意

数値 equality、quantum equality、total order は異なる観測です。

有限値は次の形で保存されます。

`(-1)^negative * magnitude * 10^exponent10`

加えて作業精度 `precision` を持ちます。

公開 observer の `coefficient()` と `magnitude()` は、非負の coefficient を
`BigInt` として返します。符号を独立に見る場合は `is_negative()` を使って
ください。これは `-0` のような GDA スタイル値で重要です。数学的な
coefficient は 0 でも、表現には負符号が残るためです。

## コンストラクタと解析

- `Decimal::make`
- `Decimal::zero`
- `Decimal::negative_zero`
- `Decimal::one`
- `Decimal::inf`
- `Decimal::nan`
- `Decimal::quiet_nan`
- `Decimal::signaling_nan`
- `Decimal::from_int`
- `Decimal::from_bigint`
- `Decimal::from_float`
- `Decimal::from_double`
- `Decimal::from_string`
- `Decimal::from_bin_float`

補足:

- `make`、`from_int`、`from_bigint` のような数値コンストラクタは、取り除ける
  `10` の冪因子を除去して有限値を正規化します。
- `from_string` は通常の 10 進表記と科学記法を受け付け、coefficient が要求精
  度に収まる場合は、解析した exponent/quantum を保持します。
- `from_string("-0")` は負のゼロを保持します。
- 不正な文字列は `None` を返します。

## 参照・正規化・比較

- `classify`
- `class_name`
- `precision`
- `sign`
- `coefficient`
- `magnitude`
- `exponent10`
- `is_negative`
- `is_signed`
- `is_finite`
- `is_infinite`
- `is_nan`
- `is_canonical`
- `is_zero`
- `is_negative_zero`
- `is_normal`
- `is_subnormal`
- `is_quiet_nan`
- `is_qnan`
- `is_signaling_nan`
- `is_snan`
- `nan_payload`
- `normalized`
- `with_precision`
- `compare`
- `compare_ctx`
- `compare_signal_ctx`
- `compare_total`
- `compare_total_magnitude`
- `min`
- `max`
- `min_ctx`
- `max_ctx`
- `min_mag_ctx`
- `max_mag_ctx`
- `minimum_ctx`
- `minimum_number_ctx`
- `maximum_ctx`
- `maximum_number_ctx`
- `minimum_magnitude_ctx`
- `minimum_number_magnitude_ctx`
- `maximum_magnitude_ctx`
- `maximum_number_magnitude_ctx`
- `clamp`
- `clamp_checked`

補足:

- `compare` は `NaN` に対して abort します。
- `compare_ctx(lhs, rhs, ctx)` は 10 進の `-1`、`0`、`1`、または quiet `NaN`
  と flags を返します。quiet NaN は `invalid_operation` を立てず、signaling
  NaN はそれを立てます。
- `compare_signal_ctx(lhs, rhs, ctx)` は数値結果の形としては `compare_ctx` と
  同じですが、NaN オペランドがあれば必ず `invalid_operation` を立てます。
- `clamp` は境界が無順序、または `NaN` を含むと abort します。`clamp_checked` はその条件を構造化された domain error に変換します。
- 共有 `Sign` observer は有限なゼロ値すべてに対して `Zero` を返し、負のゼロ
  も含みます。ゼロの符号が意味論的に重要なら `is_negative_zero()` を使ってく
  ださい。
- `class_name(ctx)` は与えられた exponent context の下で、その値の GDA 風ク
  ラス文字列を返し、normal/subnormal の区別も含みます。
- `is_canonical()` は、このパッケージがまだ代替 10 進 interchange encoding を
  持たないため、現在は `true` を返します。
- `is_qnan()` と `is_snan()` は既存の quiet/signaling NaN predicate の GDA 名
  エイリアスです。
- `Eq` は汎用 Luna-Flow 利用向けの数値的等価です。`+0 == -0` であり、NaN 同
  士も `Eq` 層では等しいと見なされます。表現レベルの違いが重要なら明示的な
  NaN observer を使ってください。

## 算術と変換

## Context API を使う場合

GDA workflow では `*_ctx` を使います。便利な operator は `DecimalFlags` を返しません。

- `neg`
- `abs`
- `copy`
- `copy_abs`
- `copy_negate`
- `copy_sign`
- `add`
- `add_ctx`
- `plus_ctx`
- `minus_ctx`
- `abs_ctx`
- `sub`
- `sub_ctx`
- `mul`
- `mul_ctx`
- `div`
- `div_ctx`
- `sqrt`
- `sqrt_ctx`
- `fma_ctx`
- `divide_integer`
- `remainder`
- `remainder_near`
- `next_plus`
- `next_minus`
- `next_toward`
- `exp_ctx`
- `ln_ctx`
- `logb_ctx`
- `scaleb_ctx`
- `to_sci_string`
- `to_eng_string`
- `shift_ctx`
- `rotate_ctx`
- `quantize`
- `rescale`
- `reduce_ctx`
- `normalize_ctx`
- `same_quantum`
- `quantum`
- `get_payload`
- `set_payload`
- `set_payload_signaling`
- `to_integral_exact`
- `to_integral_value`
- `logical_and`
- `logical_or`
- `logical_xor`
- `logical_invert`
- `to_bin_float`

対応演算子:

- `+`
- `-`
- `*`
- `/`
- 単項 `-`

変換の意味:

- 非 dyadic な 10 進値を 2 進へ変換すると近似になることがあります。
- 2 進から 10 進への変換は、現在 `BinFloat` に保存されている有限値を正確に移
  します。
- `to_sci_string(src, ctx)` と `to_eng_string(src, ctx)` は、`toSci` と
  `toEng` decTest で使われる GDA 文字列変換操作を実装します。現在の decimal
  context の下で有限数、無限大、qNaN、sNaN のテキストを解析し、canonical な
  GDA scientific または engineering テキストと変換 status flags を返します。
  この経路は構文診断、payload 境界、ゼロ digit を捨てたときの `rounded`、
  丸め方向に従った無限大または最大有限値への overflow、Etiny underflow、
  clamped zero exponent を扱います。
- `logb_ctx` は adjusted exponent を現在の context 下で Decimal 整数として返
  します。有限ゼロは `division_by_zero` 付きの `-Infinity`、無限大は
  `+Infinity`、NaN は context の quiet/payload 規則に従って伝播します。
  adjusted exponent に context 丸めが必要な場合、捨てた digit がすべてゼロな
  ら `rounded` のみを立て、`inexact` は立てません。これは GDA の整数結果意
  味論に一致します。
- `scaleb_ctx` は `self * 10^other` を現在の context 下で返します。scale
  operand は、GDA context 範囲内にある exponent-zero の有限整数でなければな
  らず、無効な scale operand は quiet `NaN` と `invalid_operation` を返しま
  す。有限結果は可能な限り coefficient cohort を保持し、その後に exponent
  bound finalization を適用します。ここには Etiny subnormal 丸め、clamped
  zero、方向付き overflow flags が含まれます。
- `shift_ctx` と `rotate_ctx` は、現在の context precision を digit 幅として
  GDA coefficient digit の移動を実装します。count operand は範囲内の有限整数
  でなければならず、無効な count は quiet `NaN` と `invalid_operation` を返
  します。quiet NaN は符号と payload を保持し、signaling NaN は quiet 化され、
  payload の切り詰めは context precision に従います。

## Context と Flags

- `DecimalContext::new`
- `DecimalContext::try_new`
- `DecimalContext::decimal32`
- `DecimalContext::decimal64`
- `DecimalContext::decimal128`
- `DecimalContext::from_arithmetic_context`
- `DecimalRoundingMode::from_arithmetic`
- `DecimalRoundingMode::to_arithmetic`
- `DecimalFlags::new`
- `DecimalFlags::combine`
- `DecimalFlags::has_error`

`*_ctx` メソッドは `(Decimal, DecimalFlags)` を返します。現在の context 層は、
non-extended GDA 演算が実行前に oversized operand を非正確に縮約した場合、
`rounded` と `inexact` に加えて `lost_digits` を報告します。
有限結果の `rounded` と `inexact`、signaling-NaN の `invalid_operation`、
ゼロ除算、未定義除算、有限結果の exponent 境界、clamp によるゼロ埋め、
overflow、subnormal、underflow を追跡します。`decimal32`、`decimal64`、
`decimal128` の各コンストラクタは期待される精度と exponent 境界を保持し、
context-aware な有限結果はそれらの境界に対して finalization されます。

`DecimalContext` は、共有 Luna-Flow `rounding` モードと 10 進ネイティブな
`decimal_rounding` モードの両方を保持します。共有フィールドは
`ArithmeticContext` と汎用 checked trait の橋渡しです。10 進ネイティブ側は
context-aware Decimal 演算で使う完全な GDA 丸め基準を担い、`HalfEven`、
`HalfUp`、`HalfDown`、`Down`、`Ceiling`、`Floor`、`Up`、`ZeroFiveUp` を扱
います。`HalfUp`、`HalfDown`、`ZeroFiveUp` のような GDA 専用モードは、共有
の Luna-Flow rounding enum がそれらを名乗らないため、
`DecimalRoundingMode::to_arithmetic()` では `None` を返します。

`DecimalContext::new` の名前付き引数 `extended` は GDA arithmetic mode を選択し、
既定値は `true` です。通常は追加設定なしで extended arithmetic を使用できます。
classic decNumber subset の挙動が必要な場合は、
`DecimalContext::new(precision=17, extended=false)` を指定してください。無効化時は
operand reduction、`lost_digits`、ゼロと cohort の cleanup、および transcendental
の classic rounding が GDA subset path に従います。

現在の exponent-bound 実装は GDA baseline 規則に従い、合法行の conformance で
検証されています。
`e_max` を超える結果は現在、無限大を生成し、`overflow`、`rounded`、
`inexact` を設定します。`e_min` より小さい正確な結果は `subnormal` を設定し、
不正確な subnormal 結果はさらに `underflow` も設定します。clamp モードでは、
数値を保ったまま coefficient に末尾ゼロを追加して exponent を下げ、
`clamped` を設定できます。

context-aware な有限加算・減算・乗算・quantize 系操作は、結果が context に収
まる限り、その演算の preferred exponent を保持します。たとえば、正確な
decimal-scale の結果 `1.20 + 3.40` は、canonical な `4.6` ではなく `4.60`
cohort に残ることができます。

`fma_ctx` は乗算を正確に計算し、3 番目のオペランドを加えたあとで初めて
context 丸めを適用します。`divide_integer` は exponent `0` の整数商を返し、
整数商が context precision に収まらない場合は `division_impossible` を報告し
ます。`remainder` はその整数商を使うため、現在実装されている有限ケースは
`x - divide_integer(x, y) * y` に従います。`remainder_near` は最も近い整数商
を使い、同距離の場合は偶数商側に解決します。

`power_ctx` は、現在の実行可能スカラー `power.decTest` 面に対する
context-aware GDA power 入口です。正確な有限整数指数、million-scale case を
含む丸め付き大整数指数、現在の context を通じて正直に finalization される終
止/非終止 reciprocal 結果、正確な `+1` と `-1` 恒等式、NaN priority 伝播、
無限大底数の非整数 sign/domain case、無限大指数 limit case、有限正底数の非
整数 power、有限非整数 power の operand-range invalid 行、そして有限な 10 の
冪底数に大きな整数指数を与えたとき強制される overflow または half-even
underflow to zero を扱います。公式 math-function `Invalid_context`
restriction 行も報告します。除外されるのは diagnostic `#` interchange/非スカラー
placeholder だけで、非診断スカラー `power` subset の gap はありません。

`log10_ctx` は context-aware GDA の 10 を底とする対数入口です。fixed-point
logarithm baseline を使い、NaN の符号/payload quiet 化を保持し、signed zero
を `-Infinity`、正の無限大を `Infinity` に写し、負の有限値と負の無限大は
`invalid_operation` 付き quiet `NaN` として拒否します。正の有限対数は現在の
context を通じて丸められ、公式 math-function `Invalid_context` restriction
行も報告します。

`exp_ctx` と `ln_ctx` は context-aware GDA 数学関数の入口です。`exp_ctx` は
10 進 range reduction を伴う fixed-point exponential evaluation を使い、NaN、
無限大、有限 signed zero（`exp(0) = 1`）、一般の有限値、overflow/underflow
境界、公式 math-function `Invalid_context` restriction 行を扱います。
`ln_ctx` は fixed-point logarithm baseline を使い、NaN、無限大、signed zero、
負の有限 invalid-operation case、正確に 1 に等しい有限値（`ln(1) = 0`）、
一般の正の有限値を扱います。

## Trait 面

## 文書の境界

公開 inventory は package interface から生成され、内部 kernel と benchmark threshold は private です。

`Decimal` は現在次を実装します。

- `@arithmetic.CompareChecked`
- `@arithmetic.DivChecked`
- `@arithmetic.ParseChecked`
- `@arithmetic.PowIntChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.SqrtChecked`
- `@def.Floating`
- `@luna-generic.Zero`
- `@luna-generic.One`
- `@luna-generic.AddMonoid`
- `@luna-generic.MulMonoid`
- `@luna-generic.AddGroup`
- `@luna-generic.Semiring`
- `@luna-generic.Ring`
- `Eq`、`Add`、`Sub`、`Mul`、`Div`、`Neg`、`Show`

挙動補足:

- `Decimal` は独立した超越関数 trait や定数 trait を実装せず、初等関数を明示的な context メソッドとして提供します。
- `Luna-Flow/arithmetic` との主要な統合面は checked arithmetic trait です。
- このパッケージは decimal32/64/128 interchange API を公開しています。
  適合状況は現在の `gda_expr` summary で示し、すべての diagnostic 行を
  実行可能と一括して主張しません。

## 公開面の補足一覧

## GDA 検証

合法な official/official0 scalar rows は完全適合し、除外は `#` placeholder/non-scalar の不正入力だけです。

`DecCoeff` は package-private であり、公開表現境界には `BigInt` を使います。
生成 interface には `Decimal::{from_string_ctx,parse,apply_ctx,trim,div_checked,compare_checked,compare_total_ctx,compare_total_magnitude_ctx,from_interchange_hex,to_interchange_hex}`
も含まれます。`DecimalInterchange` は `from_decimal`、`from_hex`、`to_decimal`、
`to_decimal_ctx`、`to_hex` と copy/canonicalization メソッドを提供します。
保存形式は `DecimalInterchange::format` で取得できます。

## 完全な公開インターフェース

次の snapshot は `0.6.0` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/decimal"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/def",
  "Luna-Flow/luna-generic",
  "moonbitlang/core/bigint",
}

// Values

// Errors

// Types and methods
pub struct Decimal {
  // private fields
}
pub fn Decimal::abs(Self) -> Self
pub fn Decimal::abs_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::add(Self, Self) -> Self
pub fn Decimal::add_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::apply_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::clamp(Self, min~ : Self, max~ : Self) -> Self
pub fn Decimal::clamp_checked(Self, min~ : Self, max~ : Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::class_name(Self, DecimalContext) -> String
pub fn Decimal::classify(Self) -> @arithmetic.FpClass
pub fn Decimal::coefficient(Self) -> @bigint.BigInt
pub fn Decimal::compare(Self, Self) -> Int
pub fn Decimal::compare_checked(Self, Self) -> Result[Int, @arithmetic.ArithmeticError]
pub fn Decimal::compare_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_signal_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::compare_total(Self, Self) -> Int
pub fn Decimal::compare_total_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::compare_total_magnitude(Self, Self) -> Int
pub fn Decimal::compare_total_magnitude_ctx(Self, Self, DecimalContext) -> (Int, DecimalFlags)
pub fn Decimal::copy(Self) -> Self
pub fn Decimal::copy_abs(Self) -> Self
pub fn Decimal::copy_negate(Self) -> Self
pub fn Decimal::copy_sign(Self, Self) -> Self
pub fn Decimal::div(Self, Self) -> Self
pub fn Decimal::div_checked(Self, Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::div_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::divide_integer(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exp_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::exponent10(Self) -> Int
pub fn Decimal::fma_ctx(Self, Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::from_bigint(@bigint.BigInt, precision? : Int) -> Self
pub fn Decimal::from_bin_float(@bin_float.BinFloat, precision? : Int) -> Self
pub fn Decimal::from_double(Double, precision? : Int) -> Self
pub fn Decimal::from_float(Float, precision? : Int) -> Self
pub fn Decimal::from_int(Int, precision? : Int) -> Self
pub fn Decimal::from_interchange_hex(String, DecimalInterchangeFormat) -> Self?
pub fn Decimal::from_interchange_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Self?
pub fn Decimal::from_string(String, precision? : Int) -> Self?
pub fn Decimal::from_string_ctx(String, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::get_payload(Self) -> @bigint.BigInt
pub fn Decimal::inf(@def.Sign, precision? : Int) -> Self
pub fn Decimal::is_canonical(Self) -> Bool
pub fn Decimal::is_finite(Self) -> Bool
pub fn Decimal::is_infinite(Self) -> Bool
pub fn Decimal::is_nan(Self) -> Bool
pub fn Decimal::is_negative(Self) -> Bool
pub fn Decimal::is_negative_zero(Self) -> Bool
pub fn Decimal::is_normal(Self, DecimalContext) -> Bool
pub fn Decimal::is_qnan(Self) -> Bool
pub fn Decimal::is_quiet_nan(Self) -> Bool
pub fn Decimal::is_signaling_nan(Self) -> Bool
pub fn Decimal::is_signed(Self) -> Bool
pub fn Decimal::is_snan(Self) -> Bool
pub fn Decimal::is_subnormal(Self, DecimalContext) -> Bool
pub fn Decimal::is_zero(Self) -> Bool
pub fn Decimal::ln_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::log10_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logb_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_and(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_invert(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_or(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::logical_xor(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::magnitude(Self) -> @bigint.BigInt
pub fn Decimal::make(@bigint.BigInt, Int, Int, mode? : @arithmetic.RoundingMode) -> Self
pub fn Decimal::max(Self, Self) -> Self
pub fn Decimal::max_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::max_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::maximum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min(Self, Self) -> Self
pub fn Decimal::min_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::min_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_mag_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minimum_number_magnitude_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::minus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::mul(Self, Self) -> Self
pub fn Decimal::mul_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::nan(precision? : Int) -> Self
pub fn Decimal::nan_payload(Self) -> @bigint.BigInt
pub fn Decimal::neg(Self) -> Self
pub fn Decimal::negative_zero(precision? : Int) -> Self
pub fn Decimal::next_minus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_plus(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::next_toward(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalize_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::normalized(Self) -> Self
pub fn Decimal::one(precision? : Int) -> Self
pub fn Decimal::parse(String, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::plus_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::power_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::precision(Self) -> Int
pub fn Decimal::quantize(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::quantum(Self) -> Int
pub fn Decimal::quiet_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::reduce_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::remainder_near(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rescale(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::rotate_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::same_quantum(Self, Self) -> Bool
pub fn Decimal::scaleb_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::set_payload(Self, @bigint.BigInt) -> Self
pub fn Decimal::set_payload_signaling(Self, @bigint.BigInt) -> Self
pub fn Decimal::shift_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sign(Self) -> @def.Sign
pub fn Decimal::signaling_nan(payload? : @bigint.BigInt, negative? : Bool, precision? : Int) -> Self
pub fn Decimal::sqrt(Self) -> Result[Self, @arithmetic.ArithmeticError]
pub fn Decimal::sqrt_ctx(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::sub(Self, Self) -> Self
pub fn Decimal::sub_ctx(Self, Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_bin_float(Self, precision? : Int, mode? : @arithmetic.RoundingMode) -> @bin_float.BinFloat
pub fn Decimal::to_eng_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::to_integral_exact(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_integral_value(Self, DecimalContext) -> (Self, DecimalFlags)
pub fn Decimal::to_interchange_hex(Self, DecimalInterchangeFormat) -> (String, DecimalFlags)
pub fn Decimal::to_interchange_hex_with_encoding(Self, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> (String, DecimalFlags)
pub fn Decimal::to_sci_string(String, DecimalContext) -> (String, DecimalFlags)
pub fn Decimal::trim(Self) -> Self
pub fn Decimal::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub fn Decimal::zero(precision? : Int) -> Self
pub impl @arithmetic.AbsContextual for Decimal
pub impl @arithmetic.AddContextual for Decimal
pub impl @arithmetic.CompareChecked for Decimal
pub impl @arithmetic.DivChecked for Decimal
pub impl @arithmetic.DivContextual for Decimal
pub impl @arithmetic.ExpContextual for Decimal
pub impl @arithmetic.MulContextual for Decimal
pub impl @arithmetic.NumericFormatContextual for Decimal
pub impl @arithmetic.ParseChecked for Decimal
pub impl @arithmetic.PowIntChecked for Decimal
pub impl @arithmetic.PowNatChecked for Decimal
pub impl @arithmetic.SqrtChecked for Decimal
pub impl @arithmetic.SqrtContextual for Decimal
pub impl @arithmetic.SubContextual for Decimal
pub impl @def.Floating for Decimal
pub impl @luna-generic.AddGroup for Decimal
pub impl @luna-generic.AddMonoid for Decimal
pub impl @luna-generic.IntegralHomomorphism for Decimal
pub impl @luna-generic.MulMonoid for Decimal
pub impl @luna-generic.NatHomomorphism for Decimal
pub impl @luna-generic.One for Decimal
pub impl @luna-generic.Ring for Decimal
pub impl @luna-generic.Semiring for Decimal
pub impl @luna-generic.Zero for Decimal
pub impl Add for Decimal
pub impl Compare for Decimal
pub impl Div for Decimal
pub impl Eq for Decimal
pub impl Mul for Decimal
pub impl Neg for Decimal
pub impl Show for Decimal
pub impl Sub for Decimal

pub struct DecimalContext {
  // private fields
} derive(Eq)
pub fn DecimalContext::clamp(Self) -> Bool
pub fn DecimalContext::decimal128() -> Self
pub fn DecimalContext::decimal32() -> Self
pub fn DecimalContext::decimal64() -> Self
pub fn DecimalContext::decimal_rounding(Self) -> DecimalRoundingMode
pub fn DecimalContext::e_max(Self) -> Int
pub fn DecimalContext::e_min(Self) -> Int
pub fn DecimalContext::exact() -> Self
pub fn DecimalContext::extended(Self) -> Bool
pub fn DecimalContext::from_arithmetic_context(@arithmetic.ArithmeticContext) -> Self
pub fn DecimalContext::gda(Self) -> Self
pub fn DecimalContext::ieee754(Self) -> Self
pub fn DecimalContext::is754version2019(Self) -> Bool
pub fn DecimalContext::new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Self
pub fn DecimalContext::precision(Self) -> Int
pub fn DecimalContext::rounding(Self) -> @arithmetic.RoundingMode
pub fn DecimalContext::tininess(Self) -> DecimalTininessDetection
pub fn DecimalContext::try_new(precision? : Int, rounding? : @arithmetic.RoundingMode, decimal_rounding? : DecimalRoundingMode, e_min? : Int, e_max? : Int, clamp? : Bool, extended? : Bool, tininess? : DecimalTininessDetection) -> Result[Self, @arithmetic.ArithmeticError]
pub fn DecimalContext::with_rounding(Self, @arithmetic.RoundingMode) -> Self
pub fn DecimalContext::with_tininess(Self, DecimalTininessDetection) -> Self

pub struct DecimalFlags {
  inexact : Bool
  rounded : Bool
  lost_digits : Bool
  invalid_operation : Bool
  division_by_zero : Bool
  overflow : Bool
  underflow : Bool
  subnormal : Bool
  clamped : Bool
  conversion_syntax : Bool
  division_impossible : Bool
  division_undefined : Bool
  invalid_context : Bool
} derive(Eq)
pub fn DecimalFlags::combine(Self, Self) -> Self
pub fn DecimalFlags::contains(Self, DecimalSignal) -> Bool
pub fn DecimalFlags::has_error(Self) -> Bool
pub fn DecimalFlags::new() -> Self

pub struct DecimalInterchange {
  // private fields
}
pub fn DecimalInterchange::canonical(Self) -> Self
pub fn DecimalInterchange::copy(Self) -> Self
pub fn DecimalInterchange::copy_abs(Self) -> Self
pub fn DecimalInterchange::copy_negate(Self) -> Self
pub fn DecimalInterchange::copy_sign(Self, Self) -> Self
pub fn DecimalInterchange::encoding(Self) -> DecimalInterchangeEncoding
pub fn DecimalInterchange::format(Self) -> DecimalInterchangeFormat
pub fn DecimalInterchange::from_decimal(Decimal, DecimalInterchangeFormat) -> (Self, DecimalFlags)
pub fn DecimalInterchange::from_decimal_with_encoding(Decimal, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> (Self, DecimalFlags)
pub fn DecimalInterchange::from_hex(String, DecimalInterchangeFormat) -> Self?
pub fn DecimalInterchange::from_hex_with_encoding(String, DecimalInterchangeFormat, DecimalInterchangeEncoding) -> Self?
pub fn DecimalInterchange::is_canonical(Self) -> Bool
pub fn DecimalInterchange::to_decimal(Self) -> Decimal
pub fn DecimalInterchange::to_decimal_ctx(Self) -> (Decimal, DecimalFlags)
pub fn DecimalInterchange::to_hex(Self) -> String

pub(all) enum DecimalInterchangeEncoding {
  DPD
  BID
} derive(Eq)

pub(all) enum DecimalInterchangeFormat {
  Decimal32
  Decimal64
  Decimal128
} derive(Eq)
pub fn DecimalInterchangeFormat::context(Self) -> DecimalContext

pub(all) enum DecimalRoundingMode {
  HalfEven
  HalfUp
  HalfDown
  Down
  Ceiling
  Floor
  Up
  ZeroFiveUp
} derive(Eq)
pub fn DecimalRoundingMode::from_arithmetic(@arithmetic.RoundingMode) -> Self
pub fn DecimalRoundingMode::to_arithmetic(Self) -> @arithmetic.RoundingMode?

pub(all) enum DecimalSignal {
  ConversionSyntax
  DivisionByZero
  DivisionImpossible
  DivisionUndefined
  InvalidContext
  InvalidOperation
  Overflow
  Underflow
  Subnormal
  Inexact
  Rounded
  Clamped
  LostDigits
} derive(Eq)

pub(all) enum DecimalTininessDetection {
  BeforeRounding
  AfterRounding
} derive(Eq)

// Type aliases

// Traits
```
<!-- generated-api-end -->
