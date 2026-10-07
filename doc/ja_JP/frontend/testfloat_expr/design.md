# `frontend/testfloat_expr` 設計

TestFloat metadata と固定幅 hex vector を解析し、`BinaryInterchange` で decode、`BinaryContext` で arithmetic、mulAdd、rem、roundToInt、整数変換、比較 function を実行し、符号化結果・整数・0/1 結果と五つの IEEE flags を比較します。invalid な整数変換は SoftFloat の sentinel が platform 依存のため flags だけを比較します。format/operation/rounding/tininess は `TestFloatSpec` parser の範囲だけです。
