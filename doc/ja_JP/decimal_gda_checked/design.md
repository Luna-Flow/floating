# `decimal_gda_checked` Design

## State Model

`GdaDecimalChecked` は一つの `GdaOutcome[Decimal]` だけを保持します。Outcome は
current defined value、next sticky context、latest raised flags、optional trapped
signal を所有します。

## Transitions

`Completed` 上の operation は value と next context を使い、new outcome を保存します。
`Trapped` 上の operation は identity transition です。これにより trap short-circuit
が explicit になり、configured control boundary を越える計算を防ぎます。

## Recovery Boundary

`resume_defined` は唯一の control escape hatch です。Defined value と sticky
context を保持し、current-step `raised` observation を clear して completed pipeline
に戻します。Binary method は plain GDA value を取り、独立 sticky context を merge
しません。Trap を `ArithmeticError` に変換することもありません。
