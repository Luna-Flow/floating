# `ball_float` Conformance

## 宣言

現在の strict ITF1788 gate は選択した 4,656/4,656 case を実行し、failed、unsupported、diagnostic はすべてゼロです。この宣言は固定 corpus revision、選択 operation phase、runner precision だけを対象とし、IEEE 1788 全体の実装宣言ではありません。

## 意味 Oracle

期待値は集合の意味で比較します。endpoint containment、set relation、boolean relation、overlap state、numeric observation、decoration ごとに専用 comparator を使います。contract が widening を許す場合は広い interval も正しい一方、exact result を失う enclosure は常に誤りです。

## 対応 Phase

strict matrix は sets、relations、observations、cancellation、add/subtract/multiply/divide、elementary core、exponential/logarithmic、general power、`atan2` を含む trigonometric、FMA、integer power、extrema を含みます。phase の operation set は互いに disjoint で、同じ row を二重計上しません。

## Decoration と Fallback

Empty、Entire、decorated NaI は別状態です。elementary kernel は directed dyadic certificate を使います。range reduction を証明できない場合、`sin`/`cos` は `[-1,1]`、`tan` は Entire を返します。inclusion は保ちますが tightness は保証しません。

## 対象外

reverse interval operation、選択 phase 外の全 decoration rule、任意 endpoint format、固定されていない upstream revision は宣言外です。

## 再現

```sh
just conformance smoke interval
just conformance fetch interval itf1788
just gate interval 8
```

provenance、phase count、strict mode、failure triage は[interval data guide](../../../testdata/interval/README.md)を参照してください。
