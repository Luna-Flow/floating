# @internal

このページは現在の `0.4.0` 基準における `@internal` パッケージを説明します。これは実装補助層であり、安定公開 API の約束ではありません。

## `BigInt` 補助

- `bigint_zero`
- `bigint_one`
- `abs_bigint`
- `sign_of_bigint`

## べき乗・桁数補助

- `pow2`
- `pow5`
- `pow10`
- `digits10`

## 正規化補助

- `remove_factor2`
- `remove_factor10`
- `exact_divide_by_power_of_ten`: 指定した `10` のべきで割り切れる場合だけ厳密商を返します。
- `trim_trailing_decimal_zeros`: 任意の上限内で末尾 10 進ゼロを除き、新しい係数・指数・除去数を返します。

## 丸め補助

- `round_positive_div`
- `round_shift`
- `compare_abs`

## 10 進解析補助

- `split_decimal_string`
