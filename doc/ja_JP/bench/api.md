# `bench` API リファレンス

リポジトリ benchmark 共通の Maremark 仕様、ペア分析、auto-tune 集約です。

## ステータス

これはリポジトリの性能基盤です。再利用 API を公開するのは `bench` だけで、データ型サブパッケージはアプリケーション API を持ちません。

## 完全な公開インターフェース

次のスナップショットはバージョン `0.7.0` の完全な生成インターフェースです。

<!-- generated-api-start -->
```moonbit
// Generated using `moon info`, DON'T EDIT IT
package "Luna-Flow/floating/bench"

import {
  "Luna-Flow/mare_mark/event",
  "Luna-Flow/mare_mark/model",
  "Luna-Flow/mare_mark/runner",
  "Luna-Flow/mare_mark/stats",
}

// Values
pub fn confirmatory_regression(Array[Double], Array[Double], UInt64) -> Result[@stats.Comparison, @stats.BootstrapError]

pub fn environment(@model.ExecutionTarget, String, String) -> @model.EnvironmentSnapshot

pub fn[Scale, Input, Expected, Output] immutable_bench(String, String, Array[Scale], (Scale) -> String, (@model.GenerationContext[Scale]) -> Input, (Input) -> String, Array[@runner.Implementation[Input, Output, Unit]], (Input) -> Expected, (Expected, Output) -> Bool, (Input) -> String, (Output) -> String) -> @runner.BenchSpec[Scale, Input, Input, Expected, Output, Unit, Output?, Output?]

pub fn is_significant_regression(@stats.Comparison) -> Bool

pub fn paired_hotspot(Array[@model.Observation], String, Int, String, String, Double, UInt64) -> Result[@stats.Comparison, @stats.BootstrapError]

pub async fn[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue] run(@runner.BenchSpec[Scale, Input, Prepared, Expected, Output, Context, State, SinkValue], @model.EnvironmentSnapshot, @event.ObservationSink, UInt64, @runner.ValidatedProtocol) -> @model.RunSummary

pub fn tune_dataset(Array[@model.Observation], String, Int, Array[String], Double) -> TuneDecision?

// Errors

// Types and methods
pub struct TuneDecision {
  dataset_id : Int
  candidate_id : String
  median_us : Double
  valid_samples : Int
}

// Type aliases

// Traits
```
<!-- generated-api-end -->

