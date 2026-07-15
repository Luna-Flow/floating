///|
fn[Result] elementary_baseline_run(
  bencher : @bench.Bench,
  name : String,
  repetitions : Int,
  operation : () -> Result,
) -> Unit {
  bencher.bench(name~, count=9, fn() {
    let mut sink = operation()
    for _ in 1..<repetitions {
      sink = operation()
    }
    bencher.keep(sink)
  })
}

///|
#skip("performance benchmark")
test "elementary immutable baseline workload" {
  let bencher = @bench.Bench()
  for precision in [53, 128, 512] {
    let label = precision.to_string() + "bit"
    let left = BinFloat::from_double(1.25, precision~)
    let right = BinFloat::from_double(0.5, precision~)
    elementary_baseline_run(bencher, "add/" + label, 4096, fn() {
      left.add(right)
    })
    elementary_baseline_run(bencher, "mul/" + label, 1024, fn() {
      left.mul(right)
    })
    elementary_baseline_run(bencher, "div/" + label, 256, fn() {
      left.div(right)
    })
    elementary_baseline_run(bencher, "sqrt/" + label, 64, fn() {
      left.sqrt().unwrap()
    })
  }
  println("ELEMENTARY_BASELINE_CHECKSUM=elementary-baseline-v1")
  println("ELEMENTARY_BASELINE_JSON=" + bencher.dump_summaries())
}
