# `ball_float_checked` 設計

`BallFloatResult` は checked interval 構築と算術を閉じます。不正端点、非有限 exact source、checked failure は error になり後続を短絡します。

decoration や `BallFlags` を保存せず、interval algorithm も追加しません。bare/decorated/context は `ball_float` の責務であり、Entire のような保守的包絡は正常な成功値です。

wrapper overhead は `O(1)` です。Entire は tightness 低下であって inclusion failure
ではないため成功値のままにし、interval domain の意味を保ちます。
