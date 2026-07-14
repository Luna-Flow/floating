# 検証

Repository は高速な development check と、有限で再現可能な conformance claim を
分離します。Corpus pass が証明するのは宣言済み format、operation、rounding mode、
target、fixture revision だけです。

## 検証 layer

| Layer | Command | 目的 |
| --- | --- | --- |
| Documentation | `just docs` | locale/file/heading/link と executable documentation example |
| Formatting | `just fmt` | MoonBit formatter |
| Pull request | `just pr [jobs]` | generated interface、all-target check、native/Python test、smoke corpus |
| IEEE decimal | `just gate decimal [jobs]` | supported target の decimal32/64/128 DPD/BID fixture |
| GDA decimal | `just gate decimal_gda [jobs]` | pinned `official`/`official0` `.decTest` legal scalar row |
| Binary | `just gate binary [jobs]` | pinned TestFloat level-1 matrix と MPFR data |
| Interval | `just gate interval [jobs]` | pinned ITF1788 strict supported phase |
| Complete | `just ci [jobs]` | generated interface、target、unit、conformance gate 全体 |

最も狭い関連 check から始め、release 前に範囲を広げます。

## 共通 conformance runner

全 suite は一つの dispatcher を使います。

```sh
just conformance <build|run|smoke|plan|fetch> \
  <decimal|decimal_gda|binary|interval> [options]
```

`decimal` は independent IEEE decimal corpus、`decimal_gda` は GDA `.decTest`、
`binary` は TestFloat と MPFR、`interval` は ITL です。

`smoke` は download なしで committed fixture を実行し、`plan` は deterministic task
を表示します。`fetch` は pinned provenance を検証して ignored data を `.tmp/` に
置き、`run` が suite を実行します。Filter、phase、target、strict mode、sharding、
JSON は `testdata/*/README.md` を参照します。

## 公開 claim

- **GDA:** 144-file `official` corpus の legal executable scalar 64,986 行と
  `official0` の legal 16,124 行を全件 pass します。141 の `#` placeholder/
  non-scalar invalid row は diagnostic exclusion で、unsupported legal behavior ではありません。
- **Binary:** 7,461,360 TestFloat vector が binary16/32/64/128 の add/subtract/
  multiply/divide/sqrt、五 rounding direction、両 tininess mode を覆い、pinned MPFR
  sqrt data が 1,055 行を追加します。
- **IEEE decimal:** committed decimal32/64/128 DPD/BID fixture が encoding、special
  value、flags、core arithmetic、全 1,024 DPD declet を native、Wasm、Wasm-GC、
  JavaScript で検証します。LLVM は gate 外です。
- **Interval:** strict ITF1788 phase が宣言済み set、relation、observation、arithmetic、
  cancellation、elementary、power、trigonometric、FMA、integer-power、extrema を
  覆います。Reverse operation は未対応です。

これは有限 claim であり、IEEE 754/1788 の全 operation、任意 resource size、全 NaN
payload policy、unpinned future corpus revision を意味しません。

## 再現性

External artifact の revision と SHA-256 は corpus manifest に固定します。Build は
backend 名の output と isolated target directory を使い、parallel job が上書きしません。
Shard は deterministic case index を選び、merged summary は exact total/failed ID を保持します。

MoonBit frontend が numeric row を parse/execute し、Python は download、task plan、
subprocess、target selection、aggregation を行います。Optional oracle がない場合に
弱い実装へ silent fallback せず、requirement 不足を明示します。

Performance evidence は semantic conformance と別です。Benchmark manifest は baseline
source、dependency、toolchain、target、schedule、sample count、dispersion limit を固定し、
performance threshold は correctness を定義しません。

## Failure triage

1. 最小 case、ID filter、phase、shard で該当 backend を再現します。
2. parse diagnostic、unsupported、legacy、executable mismatch、infrastructure failure を区別します。
3. expected/actual value、flags、context、target、corpus revision、command を記録します。
4. 対応 white-box package test で parser、arithmetic、interchange、aggregation を切り分けます。
5. 修正後に focused case、smoke fixture、backend gate、最後に `just pr`/`just ci` を実行します。

Strict support を弱める、flags を捨てる、denominator を変えることで gate を通してはいけません。

## Release gate

Publish 前に次を行います。

1. `moon.mod`、root README、localized index、standard、changelog を揃える。
2. `just docs` を実行し generated interface 差分を確認する。
3. Iteration 中は `just pr` を実行する。
4. Release candidate では `just ci` を実行する。
5. Repository GitHub Actions workflow から publish する。

Organization credential は workflow が供給するため、local `moon publish` は Luna-Flow
の release path ではありません。
