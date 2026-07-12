# `frontend/mpfr_expr` 設計

固定 MPFR の sqrt `data_check` と生成 integer-power witness を解析し、係数を `BinCoeff` に変換して `sqrt_ctx`/`pow_int_ctx` を実行、値と inexact を比較します。MPFR binding/FFI/IO ではなく、この二つの corpus 文法だけを対象とします。
