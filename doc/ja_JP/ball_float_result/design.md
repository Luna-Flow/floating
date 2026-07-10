# `ball_float_result` 設計

## 責務

この wrapper は構築・checked 演算の失敗と、正当だが広い包絡を区別します。whole-real fallback は有効な区間情報であり、算術エラーではありません。

## 境界

値を返す操作だけを持ち上げます。`Bool` を返す関係は `BallFloat` に残り、すべての合成・数値メソッドは既存エラーを短絡します。
