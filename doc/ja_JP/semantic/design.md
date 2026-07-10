# `semantic` 設計

## 目的

意味層は具体型の保存・丸め詳細を除き、厳密値、無限大、NaN、区間、エラーを特定の表現を基準にせず比較可能にします。

## 制限

これは投影であって算術エンジンではありません。Decimal context、precision、quantum、payload、flags、区間 decoration は保持しないため、それらが不要になった境界でだけ使います。
