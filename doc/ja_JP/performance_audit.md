# 0.7.1 Performance And Semantic Audit

<!-- historical-performance-baseline: 0.6.1 -->
<!-- historical-performance-baseline: 0.7.0 -->

このページは 0.7.1 最適化監査の日本語版です。0.7.0 後の四つの最適化 commit、
release review で発見・修正した意味論上の問題、および performance claim の証拠範囲を記録します。

## Scope

監査対象は `69084bc`、`7904016`、`23005ed`、`4fd41ad` と、この release tree に
追加された GDA coefficient helper および interval regression repair です。観測、規範的な
期待、実装判断、acceptance evidence を別々の事実として扱います。

## Issue Matrix

| Row | Class | Observed | Expected | Change | Acceptance evidence |
| --- | --- | --- | --- | --- | --- |
| GDA coefficient kernels | implementation gap | 小さい表現、remainder-only division、half-power 比較を追加 | coefficient identity、cohort、flags、trap、sticky status が不変 | canonical `GdaCoeff` 操作と共通 GDA finalizer を維持 | package 93 tests、frontend 8 tests、`official` 64,986/64,986、`official0` 16,124/16,124 |
| IEEE decimal paths | semantic-risk optimization | exact/bounded division が重複する generic work を省略 | exact result、rounding、quantum、flags、special values が IEEE と一致 | finite domain、factor、bound、finalization predicate で保護し、失敗時は fallback | package 94 tests、four-target IEEE 15,763/15,763 |
| Binary IEEE paths | semantic-risk optimization | exact-top、round/sticky extraction、coefficient dispatch を導入 | contextual value、rounding、flags、signed zero、interchange bits が不変 | exact coefficient を作り、全結果を contextual rounding に通す | package 68 tests、binary 7,464,503/7,464,503 |
| Interval endpoint dispatch | semantic deviation found and fixed | optimized `pown` が sign region 間で direction を再利用し、負区間で `lo > hi` または 1 ulp 欠落 | 返る interval は順序付きで数学的 image を含む | monotonicity で endpoint を選び、各候補を outward rounding；negative-half-axis を追加 | package 42 tests、integer-power 174/174、strict ITF1788 4,656/4,656 |
| Release documentation | documentation gap | module、manifest、localized prose に 0.7.0 が残った | current reference は 0.7.1、historical note は過去のまま | current metadata と同期 audit page を更新 | `python3 tools/doc_quality.py` |

## Optimization Proofs

### Exact coefficient paths

非負 coefficient `a` と正の divisor `d` に対する remainder は
`r = a - floor(a / d) * d`、`0 <= r < d` です。したがって quotient/remainder 呼出しを
remainder-only kernel に置き換えても、観測可能な remainder と Euclidean algorithm の各 step は変わりません。
GDA half-power predicate は leading decimal digit と非零 tail で `a` と
`5 * 10^(digits(a) - 1)` を比較するため、floating estimate ではありません。

IEEE decimal の exact-division path は coefficient GCD を除去し、reduced denominator が 2 と 5 以外の
素因子を持たない場合だけ有効です。exact coefficient/exponent を作った後は既存 finalizer を呼び、factor、bound、
special-value precondition が満たされなければ generic path に戻ります。最適化が変えるのは exact value への経路であり、
IEEE の rounding/flag rule ではありません。

### Binary contextual paths

有限 dyadic を `c * 2^e` と書くと、`binary_exact_top(c, e)` は最高位の exact bit を示します。これらの top の比較は、
trailing power-of-two が異なる coefficient でも alignment 前の magnitude 比較と同値です。遠い addend を捨てる際は、
最初の discarded bit と後続 bit の OR を保存し、contextual rounding が使う round/sticky predicate をそのまま保ちます。
巨大な aligned coefficient を materialize しないだけで、exact rounding input は変わりません。

### Directed interval paths

Interval operation は `image(X) subset [lo, hi]` と `lo <= hi` を満たす必要があります。exact endpoint candidate `y` に対し、
`RoundTowardNegative(y)` は lower certificate、`RoundTowardPositive(y)` は upper certificate です。`pown` の monotonicity は次の通りです。

| Domain | Positive odd power | Positive even power | Negative odd power | Negative even power |
| --- | --- | --- | --- | --- |
| negative half-axis | increasing | decreasing | decreasing | increasing |
| positive half-axis | increasing | increasing | decreasing | decreasing |
| interval containing zero | endpoint order | zero to outward-rounded maximum | pole/whole-real split | pole/whole-real split |

実装は mathematical endpoint を先に選び、その役割に合う rounding direction を適用します。zero を跨ぐ場合、有限の extremum
candidate は両方とも upper bound 用に upward rounding します。その後 `quantize_interval` が再び outward rounding を行います。
この説明は宣言済み operation と precision contract に限られ、未対応 reverse operation は含みません。

## Performance Evidence

| Area | Measurement | Interpretation |
| --- | --- | --- |
| Binary、decimal、GDA、interval kernel | `just bench all --target native` | current tree の四つの Maremark suite が valid artifact を生成 |
| Binary square policy | `just bench auto-tune --target native` | target-specific policy artifact を生成；raw observation は non-monotonic になり得るため universal threshold ではない |
| IEEE/GDA fast path | benchmark package test と conformance gate | semantic oracle が green の場合だけ performance route を採用できる |
| Interval endpoint dispatch | `src/bench/ball_float` と strict ITF1788 | ordered な outward enclosure が成立する場合だけ cost reduction を受け入れる |

生成 artifact は `.tmp/bench/` に保存され、API data として公開しません。crossover を昇格する前に対象 hardware で再実行してください。
benchmark workload は current tree の測定証拠であり、release 全体の speedup、target 間の性能同値、universal latency bound は証明しません。

## Acceptance Matrix

| Check | Result |
| --- | --- |
| `sh tools/run_moon_clean_exec.sh test src/decimal_gda --target native --deny-warn --frozen --no-parallelize` | 93/93 passed |
| `sh tools/run_moon_clean_exec.sh test src/decimal --target native --deny-warn --frozen --no-parallelize` | 94/94 passed |
| `sh tools/run_moon_clean_exec.sh test src/bin_float --target native --deny-warn --frozen --no-parallelize` | 68/68 passed |
| `sh tools/run_moon_clean_exec.sh test src/ball_float --target native --deny-warn --frozen --no-parallelize` | 42/42 passed |
| `just gate binary 8` | 7,464,503/7,464,503 passed |
| `just gate decimal 8` | 15,763/15,763 passed |
| `just gate decimal_gda 8` | 64,986/64,986 と 16,124/16,124 passed |
| `just gate interval 8` | 4,656/4,656 passed |
| `python3 tools/doc_quality.py` | version、audit page、design proof 変更後に passed |

## Reviewer Self-Review

- Contribution: pass — unexplained speed claim ではなく、具体的な optimization boundary と実際の semantic failure repair を記録。
- Writing clarity: pass — 各 proof section が representation、monotonicity、rounding direction、evidence を分離。
- Experimental strength: needs replication — native artifact は valid だが、threshold promotion 前に non-monotonic auto-tune を再測定する。
- Evaluation completeness: declared pinned corpus について pass；全標準 operation や arbitrary real input の claim ではない。
- Method soundness: pass — negative-half-axis regression と full 1788 gate で修正 branch を検証。

## Claim-Evidence Map

| Claim | Evidence | Status |
| --- | --- | --- |
| Fast coefficient route は declared numerical result を保持する | exact-kernel identity、package test、IEEE/GDA conformance | declared API と precondition の範囲で supported |
| Interval `pown` は ordered outward enclosure を保持する | monotonicity table、negative-half-axis regression、4,656 strict ITF1788 | declared forward interval surface で supported |
| この release は performance audit 済みである | native Maremark `all` と `auto-tune` artifact | measurement evidence として supported；universal speed claim ではない |
| すべての future target/operation が同等の性能を持つ | cross-target paired artifact は本監査にない | needs evidence；明示的に claim しない |

## Limits

Semantic claim は pinned corpus、public operation surface、target-specific precision rule、明示的 fallback contract に限定されます。
`0.6.1` elementary manifest は historical comparison baseline のままで、`0.7.1` が current candidate release です。benchmark 改善だけを理由に
public API、rounding rule、error signal、interval contract を変更しません。
