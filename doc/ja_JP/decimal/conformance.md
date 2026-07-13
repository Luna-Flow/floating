# `decimal` Conformance

## Contract の分離

`decimal` は IEEE 754 arithmetic/interchange surface です。General Decimal Arithmetic の sticky status と trap は `decimal_gda` が所有し、GDA corpus の通過だけでは IEEE 宣言になりません。

## 独立 IEEE Corpus

repository に commit された IEEE corpus は decimal32/64/128 DPD/BID interchange、canonical/non-canonical encoding、special value、flag、total order、core arithmetic を扱います。DPD fixture は 1,024 個の declet をすべて列挙します。

## Oracle の層

mandatory operation vector は exact integer/rational construction と記録済み DPD/BID bridge を使います。elementary family は利用可能な独立 high-precision または interval oracle を使います。result value/encoded bits と IEEE flags は別に記録し、もっともらしい値が flag error を隠せないようにします。

## Targets

`just ieee-ci` は native、Wasm、Wasm-GC、JavaScript で実行します。必要な local artifact が repository にないため LLVM は除外します。target-specific coefficient dispatch は value、encoding、flags を変更してはなりません。

## 境界

固定 matrix は有限で、IEEE 754 の全 operation、全 payload propagation policy、全 decimal input を宣言しません。追加の `dd*`/`dq*` decTest row は diagnostic であり IEEE oracle ではありません。

## 再現

```sh
just conformance smoke decimal
just ieee-ci
just decimal-kernel-ci
```

corpus provenance、vector family、failure record は[decimal data guide](../../../testdata/decimal/README.md)を参照してください。
