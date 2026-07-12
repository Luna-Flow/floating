# `frontend/gda_expr` 設計

`.decTest` を context、source span、`numeric_expr` を含む case に解析し、operation を正規化して `Decimal` context API に写像します。結果 cohort と flags を比較し、case は Executable/Diagnostic/Legacy/Unsupported に分類、shard は安定位置で選択します。

corpus download、ファイル/プロセス、十進アルゴリズムは担当しません。ファイルと終了コードは `cli/gda_expr_cli`、corpus 編成は Python tooling が担当します。公式 corpus の diagnostic は `#` placeholder/non-scalar の不正入力だけで、合法行に unsupported/legacy はなく全件通過します。

## Data flow と純粋境界

parse、分類、実行、summary fold は決定的な pure transformation です。corpus download、file IO、process exit は外側の tooling が担当し、case を white-box、CLI、shard runner で再利用できます。

## Failure 分類

`Executable` の不一致だけが意味論 failure です。公式 corpus の診断は `#` 不正 placeholder だけで、legacy/unsupported は regression です。
