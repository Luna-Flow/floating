# `ball_float` チュートリアル

## 正確埋め込み

```moonbit
let x = @bin_float.BinFloat::make(
  @bin_float.BinCoeff::from_uint64(3UL),
  -1,
  32,
)
let ball = @ball_float.BallFloat::exact(x)
inspect(ball.to_string(), content="3p-1 +/- 0")
```

要求する精度が元の値を正確に表せない場合でも、`exact` は包含関係を落とさず、必要な分だけ半径を広げます。

## 10 進値から包絡を作る

```moonbit
let d = @decimal.Decimal::from_string("12.34", precision=32).unwrap()
let ball = @ball_float.BallFloat::exact(d.to_bin_float(precision=32))
```

ここで得られるのは `BinFloat` 中心と誤差半径に基づく包絡であり、10 進値をそのまま正確に移し替えたものではありません。

## 関係を見る

```moonbit
let a = @ball_float.BallFloat::new(
  @bin_float.BinFloat::from_int(10, precision=16),
  @bin_float.BinFloat::from_int(1, precision=16),
)
let b = @ball_float.BallFloat::new(
  @bin_float.BinFloat::from_int(15, precision=16),
  @bin_float.BinFloat::from_int(1, precision=16),
)
inspect(a.separated_from(b).to_string(), content="true")
```

関係 API は次のように使います。

- `contains`: 点が包絡に含まれるか
- `overlaps`: 2 つの包絡が重なるか
- `definitely_lt` / `definitely_gt`: 順序が実際に証明できる場合だけ使う

## Ball 算術

```moonbit
let c = a + b
let p = a * b
```

返される ball は真の結果を包むことを目的としており、単なる「誤差タグ付きの厳密スカラー」ではありません。中心を低精度へ戻すときの変位も半径へ織り込まれます。
