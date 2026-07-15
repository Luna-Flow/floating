# `bench/ball_float` 設計

## 責務

二進カーネル、区間コア、checked wrapper のコストを分離します。

## データフロー

正確な singleton interval により add、multiply、divide を `BinFloat` 参照値と比較します。

## 不変条件

コアと checked の出力は参照値を中心とする singleton interval を保ちます。

## 副作用

Maremark が calibration と timing を、Python runner が process と artifact IO を担当します。

