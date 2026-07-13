# `consistency` 設計

## 責務

cross-package law と public-surface audit 用 white-box package です。

## データフロー

numeric package 間の alias、capability trait、checked wrapper、semantic projection、migration invariant を比較します。

## アルゴリズムと不変条件

witness は小さく deterministic です。external corpus completeness は conformance runner が担当します。

## 失敗と副作用

runtime API と IO はなく、failure は contract mismatch を示す test assertion です。

## 実装上のトレードオフ

cross-package law を集中すると drift を検出できますが、package-local algorithm detail は所有 package の white-box test に残します。

## 安定性

repository infrastructure として保守されます。生成宣言は runner とともに変更され得るため、downstream compatibility は保証しません。
