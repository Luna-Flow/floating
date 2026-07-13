# `decimal_gda` Conformance

## 公開結果

固定 official corpus の legal executable scalar row 64,986/64,986 がすべて通過し、failed、unsupported、legacy はゼロです。残り 141 row は `#` placeholder または non-scalar invalid input で、legal denominator 外の diagnostic として報告します。

## Legacy Corpus

固定 `official0` corpus の legal executable row 16,124/16,124 が通過します。historical compatibility check 用であり、現在の surface の定義ではありません。

## 状態の意味

各 operation は GDA-defined result、今回 raised された flags、sticky status を蓄積した next context を持つ `GdaOutcome` を返します。trap を有効にすると outcome variant は変わりますが、defined result は失われません。

## Runner Model

document は一度だけ parse し、directive state を case ごとに snapshot し、deterministic shard が disjoint case position を実行します。executable、diagnostic、unsupported、legacy、passed、failed count は分離します。

## 境界

宣言は固定 corpus の legal scalar row だけを対象にします。placeholder/non-scalar invalid row、future directive、固定されていない revision、無限の decimal string 空間は対象外です。

## 再現

```sh
just smoke
just decimal-gda-ci 8
just conformance run decimal_gda --corpus official0 --strict-supported
```

manifest、filter、phase、JSON output、failure triage は[decimal data guide](../../../testdata/decimal/README.md)を参照してください。
