# `cli/itl_expr_cli` 設計

## 責務

ITL interval case の filesystem/JSON adapter です。

## データフロー

ITL file を読み、optional operation filter を適用し、case を `frontend/itl_expr` に委譲して stable summary を出力します。

## アルゴリズムと不変条件

unsupported case は明示したままです。strict mode は gate success だけを変更し、case disposition は書き換えません。

## 失敗と副作用

filesystem access と output が effect で、interval parse と arithmetic は pure package call のままです。

## 実装上のトレードオフ

interval semantics の重複を避ける一方、phase planning は Python tooling に委ねます。

## 安定性

repository infrastructure として保守されます。生成宣言は runner とともに変更され得るため、downstream compatibility は保証しません。
