# @decimal.Decimal

このページは現在のリポジトリ実装を追跡しており、`0.4.0` API 基準に、第一段
階の GDA 表現移行を加えたものとして書かれています。

## 表現

有限値は次の形で保存されます。

`(-1)^negative * magnitude * 10^exponent10`

加えて作業精度 `precision` を持ちます。

公開 observer の `coefficient()` は、既存のスカラー意味論との互換性のため、
引き続き符号付き coefficient を返します。符号を独立に見たい場合は
`magnitude()` と `is_negative()` を使ってください。これは `-0` のような GDA
スタイル値で重要です。数学的な coefficient は 0 でも、表現には負符号が残る
ためです。

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
- `clamp`

補足:

- `compare` は `NaN` に対して abort します。
- `compare_ctx(lhs, rhs, ctx)` は 10 進の `-1`、`0`、`1`、または quiet `NaN`
  と flags を返します。quiet NaN は `invalid_operation` を立てず、signaling
  NaN はそれを立てます。
- `compare_signal_ctx(lhs, rhs, ctx)` は数値結果の形としては `compare_ctx` と
  同じですが、NaN オペランドがあれば必ず `invalid_operation` を立てます。
- `clamp` は境界が無順序、または `NaN` を含むと abort します。
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
- `DecimalContext::exact`
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

現在の exponent-bound 実装は完全な conformance ではなく GDA baseline です。
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
restriction 行も報告します。残っている conformance gap は、非診断スカラー
`power` subset ではなく diagnostic interchange/非スカラー coverage です。

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

`DecCoeff` は `from_bigint`、`to_bigint`、`digits10`、`is_zero`、`to_string` を提供します。
生成 interface には `Decimal::{from_string_ctx,parse,apply_ctx,trim,div_checked,compare_checked,compare_total_ctx,compare_total_magnitude_ctx,from_interchange_hex,to_interchange_hex}`
も含まれます。`DecimalInterchange` は `from_decimal`、`from_hex`、`to_decimal`、
`to_decimal_ctx`、`to_hex` と copy/canonicalization メソッドを提供します。
保存形式は `DecimalInterchange::format` で取得できます。
