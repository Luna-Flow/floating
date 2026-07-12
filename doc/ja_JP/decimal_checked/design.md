# `decimal_checked` 設計

`DecimalResult` は左から短絡する checked pipeline です。parse/checked operation が error を導入し、その後は実行しません。`bind` は新しい error、`map` は成功値の変換だけです。

`DecimalContext` と `DecimalFlags` を保持しないため GDA status pipeline ではありません。cohort、clamp、指数境界、flags が必要なら `decimal` の `*_ctx` を使います。

composition 自体は底層演算以外 `O(1)` です。一つの型に short-circuit error と
status accumulation の二つの data flow を混在させないため context/flags を持ちません。
