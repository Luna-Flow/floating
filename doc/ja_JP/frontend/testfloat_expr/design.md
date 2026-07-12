# `frontend/testfloat_expr` 設計

TestFloat metadata と固定幅 hex vector を解析し、`BinaryInterchange` で decode、`BinaryContext` で add/sub/mul/div/sqrt を実行し、符号化結果と五つの IEEE flags を比較します。format/operation/rounding/tininess は `TestFloatSpec` parser の範囲だけです。
