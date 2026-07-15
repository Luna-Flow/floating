# `frontend/mpfr_expr` 設計

固定 MPFR の sqrt `data_check`、生成 integer-power witness、29-operation
elementary matrix を解析し、係数を `BinCoeff` に変換して対応する contextual
operation を実行し、値と inexact/invalid/division-by-zero status を比較します。
MPFR binding ではなく runtime C FFI/IO もありません。development-only generator
だけが MPFR 4.2.2 と必須 nearest-away wrapper を使い、release package は
MPFR/GMP を link しません。
