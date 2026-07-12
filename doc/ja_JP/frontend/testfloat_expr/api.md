# `frontend/testfloat_expr` API

`TestFloatSpec::parse(function, rounding, tininess?)` が format/operation/rounding/tininess を検証し、`parse_testfloat` が typed document、`execute_document` が stable shard の結果と件数を返します。

対象は binary16/32/64/128 の Add/Subtract/Multiply/Divide/SquareRoot だけです。summary success は選択行の値と flags が一致したことだけを意味します。
