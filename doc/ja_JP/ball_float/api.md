# `ball_float` API

## 安定性

bare/decorated interval 構築、relation、forward arithmetic、context、flags は
`0.6.0` API です。reverse operation と tightness 保証は契約外です。

このページは `0.6.0` 基準における `@ball_float.BallFloat`、
`@ball_float.Decoration`、`@ball_float.BallFloatDecorated` を説明します。

## 意味

`BallFloat` は次の包絡を表します。

`center +/- radius`

現在の実装ではこれを `BinFloat` の下界・上界として保持し、できるだけ狭い区間よりも、包絡を絶対に落とさないことを優先します。

## 構築

- `BallFloat::new`
- `BallFloat::exact`
- `BallFloat::from_bounds`
- `BallFloat::from_coefficient`
- `BallFloat::from_int`
- `BallFloat::from_float`
- `BallFloat::from_double`

`from_coefficient` は非負の `@bin_float.BinCoeff` と独立した `negative?` 符号を
受け取ります。二進 stack の `BigInt` constructor は廃止され、Decimal の
`BigInt` 境界は維持されます。

制約:

- 中心値は有限でなければなりません。
- 半径は有限かつ非負でなければなりません。
- `exact`、`from_float`、`from_double` は非有限入力で abort します。

補足:

- 中心値の再量子化で生じる変位は半径へ加えられ、包絡が縮まないようにします。
- 半径の量子化は常に外向きに丸められます。

## アクセサと区間形状

- `lower_bound`
- `upper_bound`
- `center`
- `radius`
- `precision`
- `classify`
- `sign`
- `is_bounded`
- `is_entire`
- `contains_zero`
- `normalized`
- `with_precision`

補足:

- `center()` と `radius()` は非有界区間では abort します。
- 包絡が負値と正値の両方をまたぐと `sign()` は `Sign::Zero` を返します。
- `classify()` は非有界区間に対して `Infinity` を返します。

## 関係と比較

- `contains`
- `overlaps`
- `separated_from`
- `definitely_lt`
- `definitely_le`
- `definitely_gt`
- `maybe_eq`

補足:

- これらは enclosure relation であり、scalar の全順序を装いません。

## 算術と checked capability の挙動

- `add`
- `sub`
- `mul`
- `div`
- `abs`
- `neg`
- `pow_interval`
- `sin_interval`
- `cos_interval`
- `tan_interval`

対応演算子:

- `+`
- `-`
- `*`
- `/`
- 単項 `-`

checked 挙動メモ:

- checked division は分母包絡が `0` を含むと whole-real enclosure へ広がることがあります。
- checked integer power は enclosure の正しさを保ち、零交差を含む逆冪でも同じ whole-real fallback を使います。
- `BallFloat` は scalar `CompareChecked` を実装しません。
- 一般の冪は IEEE 1788 の非負底定義域に従い、負底の整数冪は引き続き `pown` が担います。
- このパッケージは双曲・逆三角関数、微積分、行列、複素 ball、特殊関数をまだ公開しません。

## Decorated interval

`BallFloatDecorated` は `BallFloat` と同じ `ball_float` パッケージに属します。
利用側が import するのは `Luna-Flow/floating/ball_float` だけであり、独立した
`Luna-Flow/floating/decorated_ball_float` パッケージはありません。bare
interval、decorated interval、context、IEEE 1788 の集合意味論は一つの
パッケージ境界を共有します。

`Decoration` は弱い順に `Ill`、`Trv`、`Def`、`Dac`、`Com` です。
`BallFloatDecorated` は underlying `BallFloat`、decoration、独立した NaI
状態を保持します。

- `BallFloatDecorated::new` は bare interval を包みます。
- `BallFloatDecorated::nai` は NaI を構築します。NaI は `Ill` ですが Empty
  ではありません。
- `interval`、`decoration`、`is_nai` で三つの状態を観測できます。
- Empty は `Trv` に正規化され、non-common interval の `Com` は `Dac` に
  下がります。
- 演算結果は入力と演算自身の最も弱い decoration を取るため、評価中に
  等級が上がることはありません。
- 部分定義域、0 除算の可能性、三角関数の極では演算等級が `Trv` に下がります。
- 数値演算は NaI を伝播し、NaI を含む Boolean relation は `false`、
  `overlap_state` は `Undefined` を返します。

decorated 型は集合演算、relation、算術、cancellation、初等関数、FMA、
整数冪、極値、context 操作を公開し、`+`、`-`、`*`、`/`、`Show` に対応します。

## Trait 面

## Context と status

`BallContext` は端点を directed rounding し、`BallFlags` は inexact、overflow、underflow を返します。set semantics は変わりません。

`BallFloat` は現在次を実装します。

- `@def.Floating`
- `@arithmetic.Contains`
- `@arithmetic.Overlaps`
- `@arithmetic.DefinitelyLt`
- `@arithmetic.DefinitelyLe`
- `@arithmetic.MaybeEq`
- `@arithmetic.DivChecked`
- `@arithmetic.PowNatChecked`
- `@arithmetic.PowIntChecked`
- `Eq`、`Add`、`Sub`、`Mul`、`Div`、`Neg`、`Show`

## 完全な公開インターフェース

次の snapshot は `0.6.0` の完全な生成 package interface です。公開宣言が名前と signature の基準で、前の説明は挙動別に整理しています。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/ball_float"

import {
  "Luna-Flow/arithmetic",
  "Luna-Flow/floating/bin_float",
  "Luna-Flow/floating/def",
  "moonbitlang/core/debug",
}

// Values

// Errors

// Types and methods
pub struct BallContext {
  // private fields
}
pub fn BallContext::binary32() -> Self
pub fn BallContext::binary64() -> Self
pub fn BallContext::e_max(Self) -> Int
pub fn BallContext::e_min(Self) -> Int
pub fn BallContext::new(precision? : Int, e_min? : Int, e_max? : Int) -> Self
pub fn BallContext::precision(Self) -> Int
pub fn BallContext::try_new(precision? : Int, e_min? : Int, e_max? : Int) -> Result[Self, @arithmetic.ArithmeticError]

pub struct BallFlags {
  inexact : Bool
  overflow : Bool
  underflow : Bool
} derive(Eq)
pub fn BallFlags::combine(Self, Self) -> Self
pub fn BallFlags::inexact(Self) -> Bool
pub fn BallFlags::new() -> Self
pub fn BallFlags::overflow(Self) -> Bool
pub fn BallFlags::underflow(Self) -> Bool

pub struct BallFloat {
  // private fields
} derive(Eq)
pub fn BallFloat::abs(Self) -> Self
pub fn BallFloat::add(Self, Self) -> Self
pub fn BallFloat::add_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::apply_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::cancel_minus(Self, Self) -> Self
pub fn BallFloat::cancel_plus(Self, Self) -> Self
pub fn BallFloat::center(Self) -> @bin_float.BinFloat
pub fn BallFloat::classify(Self) -> @arithmetic.FpClass
pub fn BallFloat::contains(Self, @bin_float.BinFloat) -> Bool
pub fn BallFloat::contains_zero(Self) -> Bool
pub fn BallFloat::convex_hull(Self, Self) -> Self
pub fn BallFloat::cos_interval(Self) -> Self
pub fn BallFloat::definitely_gt(Self, Self) -> Bool
pub fn BallFloat::definitely_le(Self, Self) -> Bool
pub fn BallFloat::definitely_lt(Self, Self) -> Bool
pub fn BallFloat::disjoint(Self, Self) -> Bool
pub fn BallFloat::div(Self, Self) -> Self
pub fn BallFloat::div_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::empty(precision? : Int) -> Self
pub fn BallFloat::exact(@bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::exp10_interval(Self) -> Self
pub fn BallFloat::exp2_interval(Self) -> Self
pub fn BallFloat::exp_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::exp_interval(Self) -> Self
pub fn BallFloat::fma(Self, Self, Self) -> Self
pub fn BallFloat::from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::from_coefficient(@bin_float.BinCoeff, precision? : Int, negative? : Bool) -> Self
pub fn BallFloat::from_double(Double, precision? : Int) -> Self
pub fn BallFloat::from_float(Float, precision? : Int) -> Self
pub fn BallFloat::from_int(Int, precision? : Int) -> Self
pub fn BallFloat::interior(Self, Self) -> Bool
pub fn BallFloat::intersection(Self, Self) -> Self
pub fn BallFloat::is_bounded(Self) -> Bool
pub fn BallFloat::is_common_interval(Self) -> Bool
pub fn BallFloat::is_empty(Self) -> Bool
pub fn BallFloat::is_entire(Self) -> Bool
pub fn BallFloat::is_singleton(Self) -> Bool
pub fn BallFloat::less(Self, Self) -> Bool
pub fn BallFloat::ln_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::ln_interval(Self) -> Self
pub fn BallFloat::log10_interval(Self) -> Self
pub fn BallFloat::log2_interval(Self) -> Self
pub fn BallFloat::lower_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::magnitude(Self) -> @bin_float.BinFloat
pub fn BallFloat::maximum(Self, Self) -> Self
pub fn BallFloat::maybe_eq(Self, Self) -> Bool
pub fn BallFloat::midpoint(Self) -> @bin_float.BinFloat
pub fn BallFloat::midpoint_ctx(Self, BallContext) -> (@bin_float.BinFloat, BallFlags)
pub fn BallFloat::mignitude(Self) -> @bin_float.BinFloat
pub fn BallFloat::minimum(Self, Self) -> Self
pub fn BallFloat::mul(Self, Self) -> Self
pub fn BallFloat::mul_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::neg(Self) -> Self
pub fn BallFloat::new(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Self
pub fn BallFloat::normalized(Self) -> Self
pub fn BallFloat::overlap_state(Self, Self) -> OverlapState
pub fn BallFloat::overlaps(Self, Self) -> Bool
pub fn BallFloat::pow_interval(Self, Self) -> Self
pub fn BallFloat::pown(Self, Int) -> Self
pub fn BallFloat::precedes(Self, Self) -> Bool
pub fn BallFloat::precision(Self) -> Int
pub fn BallFloat::radius(Self) -> @bin_float.BinFloat
pub fn BallFloat::radius_extended(Self) -> @bin_float.BinFloat
pub fn BallFloat::reciprocal(Self) -> Self
pub fn BallFloat::separated_from(Self, Self) -> Bool
pub fn BallFloat::set_equal(Self, Self) -> Bool
pub fn BallFloat::sign(Self) -> @def.Sign
pub fn BallFloat::sin_interval(Self) -> Self
pub fn BallFloat::sqrt_interval(Self) -> Self
pub fn BallFloat::square(Self) -> Self
pub fn BallFloat::strictly_less(Self, Self) -> Bool
pub fn BallFloat::strictly_precedes(Self, Self) -> Bool
pub fn BallFloat::sub(Self, Self) -> Self
pub fn BallFloat::sub_ctx(Self, Self, BallContext) -> (Self, BallFlags)
pub fn BallFloat::subset(Self, Self) -> Bool
pub fn BallFloat::tan_interval(Self) -> Self
pub fn BallFloat::try_exact(@bin_float.BinFloat, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_bounds(@bin_float.BinFloat, @bin_float.BinFloat, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_double(Double, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::try_from_float(Float, precision? : Int) -> Result[Self, @arithmetic.ArithmeticError]
pub fn BallFloat::upper_bound(Self) -> @bin_float.BinFloat
pub fn BallFloat::whole(precision? : Int) -> Self
pub fn BallFloat::width(Self) -> @bin_float.BinFloat
pub fn BallFloat::with_precision(Self, Int, @arithmetic.RoundingMode) -> Self
pub impl @arithmetic.Contains for BallFloat
pub impl @arithmetic.DefinitelyLe for BallFloat
pub impl @arithmetic.DefinitelyLt for BallFloat
pub impl @arithmetic.DivChecked for BallFloat
pub impl @arithmetic.MaybeEq for BallFloat
pub impl @arithmetic.Overlaps for BallFloat
pub impl @arithmetic.PowIntChecked for BallFloat
pub impl @arithmetic.PowNatChecked for BallFloat
pub impl @def.Floating for BallFloat
pub impl Add for BallFloat
pub impl Div for BallFloat
pub impl Mul for BallFloat
pub impl Neg for BallFloat
pub impl Show for BallFloat
pub impl Sub for BallFloat

pub struct BallFloatDecorated {
  // private fields
} derive(Eq)
pub fn BallFloatDecorated::abs(Self) -> Self
pub fn BallFloatDecorated::add(Self, Self) -> Self
pub fn BallFloatDecorated::apply_ctx(Self, BallContext) -> (Self, BallFlags)
pub fn BallFloatDecorated::cancel_minus(Self, Self) -> Self
pub fn BallFloatDecorated::cancel_plus(Self, Self) -> Self
pub fn BallFloatDecorated::contains(Self, @bin_float.BinFloat) -> Bool
pub fn BallFloatDecorated::convex_hull(Self, Self) -> Self
pub fn BallFloatDecorated::cos_interval(Self) -> Self
pub fn BallFloatDecorated::decoration(Self) -> Decoration
pub fn BallFloatDecorated::disjoint(Self, Self) -> Bool
pub fn BallFloatDecorated::div(Self, Self) -> Self
pub fn BallFloatDecorated::exp10_interval(Self) -> Self
pub fn BallFloatDecorated::exp2_interval(Self) -> Self
pub fn BallFloatDecorated::exp_interval(Self) -> Self
pub fn BallFloatDecorated::fma(Self, Self, Self) -> Self
pub fn BallFloatDecorated::interior(Self, Self) -> Bool
pub fn BallFloatDecorated::intersection(Self, Self) -> Self
pub fn BallFloatDecorated::interval(Self) -> BallFloat
pub fn BallFloatDecorated::is_common_interval(Self) -> Bool
pub fn BallFloatDecorated::is_empty(Self) -> Bool
pub fn BallFloatDecorated::is_entire(Self) -> Bool
pub fn BallFloatDecorated::is_nai(Self) -> Bool
pub fn BallFloatDecorated::is_singleton(Self) -> Bool
pub fn BallFloatDecorated::less(Self, Self) -> Bool
pub fn BallFloatDecorated::ln_interval(Self) -> Self
pub fn BallFloatDecorated::log10_interval(Self) -> Self
pub fn BallFloatDecorated::log2_interval(Self) -> Self
pub fn BallFloatDecorated::maximum(Self, Self) -> Self
pub fn BallFloatDecorated::minimum(Self, Self) -> Self
pub fn BallFloatDecorated::mul(Self, Self) -> Self
pub fn BallFloatDecorated::nai(precision? : Int) -> Self
pub fn BallFloatDecorated::neg(Self) -> Self
pub fn BallFloatDecorated::new(BallFloat, decoration? : Decoration) -> Self
pub fn BallFloatDecorated::overlap_state(Self, Self) -> OverlapState
pub fn BallFloatDecorated::pos(Self) -> Self
pub fn BallFloatDecorated::pow_interval(Self, Self) -> Self
pub fn BallFloatDecorated::pown(Self, Int) -> Self
pub fn BallFloatDecorated::precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::reciprocal(Self) -> Self
pub fn BallFloatDecorated::set_equal(Self, Self) -> Bool
pub fn BallFloatDecorated::sin_interval(Self) -> Self
pub fn BallFloatDecorated::sqrt_interval(Self) -> Self
pub fn BallFloatDecorated::square(Self) -> Self
pub fn BallFloatDecorated::strictly_less(Self, Self) -> Bool
pub fn BallFloatDecorated::strictly_precedes(Self, Self) -> Bool
pub fn BallFloatDecorated::sub(Self, Self) -> Self
pub fn BallFloatDecorated::subset(Self, Self) -> Bool
pub fn BallFloatDecorated::tan_interval(Self) -> Self
pub impl Add for BallFloatDecorated
pub impl Div for BallFloatDecorated
pub impl Mul for BallFloatDecorated
pub impl Show for BallFloatDecorated
pub impl Sub for BallFloatDecorated

pub(all) enum Decoration {
  Ill
  Trv
  Def
  Dac
  Com
} derive(Eq, @debug.Debug)
pub impl Show for Decoration

pub(all) enum OverlapState {
  Undefined
  BothEmpty
  FirstEmpty
  SecondEmpty
  Before
  Meets
  OverlapsState
  Starts
  ContainedBy
  Finishes
  EqualIntervals
  After
  MetBy
  OverlappedBy
  StartedBy
  ContainsInterval
  FinishedBy
} derive(Eq, @debug.Debug)

// Type aliases

// Traits
```
<!-- generated-api-end -->
