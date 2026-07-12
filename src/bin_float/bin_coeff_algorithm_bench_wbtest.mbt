///|
fn bin_coeff_autotune_pattern(limbs : Int, phase : Int) -> BinCoeff {
  let bits = limbs * 32
  let mut value = 1N << (bits - 1)
  let mut index = phase % 19
  while index < bits - 1 {
    value = value | (1N << index)
    index += 19 + phase % 7
  }
  BinCoeff::parse((value | 1N).to_string()).unwrap()
}

///|
fn bin_coeff_autotune_bench(
  bencher : @bench.Bench,
  algorithm : String,
  operation : String,
  limbs : Int,
  run : () -> Unit,
) -> Unit {
  bencher.bench(
    name="\{algorithm}/\{operation}/\{limbs}/balanced",
    count=11,
    run,
  )
}

///|
#skip("offline multiplication threshold autotune")
test "BinCoeff multiplication and square threshold autotune" {
  let bencher = @bench.Bench()
  for
    limbs in [
      4, 5, 8, 12, 16, 24, 30, 31, 32, 33, 40, 48, 64, 80, 94, 95, 96, 97, 112, 128,
    ] {
    let left = bin_coeff_autotune_pattern(limbs, 3)
    let right = bin_coeff_autotune_pattern(limbs - 1, 11)
    bin_coeff_autotune_bench(bencher, "schoolbook", "mul", limbs, fn() {
      bencher.keep(bin_coeff_mul_schoolbook(left, right))
    })
    bin_coeff_autotune_bench(bencher, "karatsuba", "mul", limbs, fn() {
      bencher.keep(bin_coeff_mul_karatsuba(left, right))
    })
    if limbs >= 64 {
      bin_coeff_autotune_bench(bencher, "toom3", "mul", limbs, fn() {
        bencher.keep(bin_coeff_mul_toom3(left, right))
      })
    }
    if limbs >= 5 {
      bin_coeff_autotune_bench(bencher, "specialized", "square", limbs, fn() {
        bencher.keep(bin_coeff_square_schoolbook(left))
      })
      bin_coeff_autotune_bench(bencher, "schoolbook", "square", limbs, fn() {
        bencher.keep(bin_coeff_mul_schoolbook(left, left))
      })
    }
  }
  println("BIN_COEFF_AUTOTUNE_JSON=" + bencher.dump_summaries())
}

///|
#skip("offline NTT threshold autotune")
test "BinCoeff Toom-3 and NTT threshold autotune" {
  let bencher = @bench.Bench()
  for limbs in [512, 768, 1024, 1536, 2048, 2560, 3072, 3584, 4096, 5120] {
    let left = bin_coeff_autotune_pattern(limbs, 5)
    let right = bin_coeff_autotune_pattern(limbs - 1, 13)
    bin_coeff_autotune_bench(bencher, "karatsuba", "mul", limbs, fn() {
      bencher.keep(bin_coeff_mul_karatsuba(left, right))
    })
    bin_coeff_autotune_bench(bencher, "toom3", "mul", limbs, fn() {
      bencher.keep(bin_coeff_mul_toom3(left, right))
    })
    if bin_coeff_ntt_fits(left, right) {
      bin_coeff_autotune_bench(bencher, "ntt", "mul", limbs, fn() {
        bencher.keep(bin_coeff_mul_ntt(left, right))
      })
    }
    bin_coeff_autotune_bench(bencher, "toom3", "square", limbs, fn() {
      bencher.keep(bin_coeff_mul_toom3(left, left))
    })
    if bin_coeff_ntt_fits(left, left) {
      bin_coeff_autotune_bench(bencher, "ntt", "square", limbs, fn() {
        bencher.keep(bin_coeff_square_ntt(left))
      })
    }
  }
  println("BIN_COEFF_AUTOTUNE_JSON=" + bencher.dump_summaries())
}

///|
#skip("offline square crossover autotune")
test "BinCoeff specialized and recursive square crossover autotune" {
  let bencher = @bench.Bench()
  for limbs in [128, 160, 192, 224, 256, 320, 384, 448, 512, 640, 768] {
    let value = bin_coeff_autotune_pattern(limbs, 17)
    bin_coeff_autotune_bench(bencher, "specialized", "square", limbs, fn() {
      bencher.keep(bin_coeff_square_schoolbook(value))
    })
    bin_coeff_autotune_bench(bencher, "karatsuba", "square", limbs, fn() {
      bencher.keep(bin_coeff_mul_karatsuba(value, value))
    })
    bin_coeff_autotune_bench(bencher, "toom3", "square", limbs, fn() {
      bencher.keep(bin_coeff_mul_toom3(value, value))
    })
    if bin_coeff_ntt_fits(value, value) {
      bin_coeff_autotune_bench(bencher, "ntt", "square", limbs, fn() {
        bencher.keep(bin_coeff_square_ntt(value))
      })
    }
  }
  println("BIN_COEFF_AUTOTUNE_JSON=" + bencher.dump_summaries())
}

///|
#skip("offline recursive multiplication crossover autotune")
test "BinCoeff schoolbook Karatsuba and Toom-3 crossover autotune" {
  let bencher = @bench.Bench()
  for
    limbs in [
      96, 104, 112, 120, 128, 136, 144, 152, 160, 176, 192, 224, 256, 320, 384, 448,
      512, 640, 768, 896, 1024, 1280, 1536, 1792, 2048,
    ] {
    let left = bin_coeff_autotune_pattern(limbs, 7)
    let right = bin_coeff_autotune_pattern(limbs - 1, 15)
    bin_coeff_autotune_bench(bencher, "schoolbook", "mul", limbs, fn() {
      bencher.keep(bin_coeff_mul_schoolbook(left, right))
    })
    bin_coeff_autotune_bench(bencher, "karatsuba", "mul", limbs, fn() {
      bencher.keep(bin_coeff_mul_karatsuba(left, right))
    })
    bin_coeff_autotune_bench(bencher, "toom3", "mul", limbs, fn() {
      bencher.keep(bin_coeff_mul_toom3(left, right))
    })
  }
  println("BIN_COEFF_AUTOTUNE_JSON=" + bencher.dump_summaries())
}

///|
#skip("offline large square crossover autotune")
test "BinCoeff large specialized Toom-3 and NTT square crossover autotune" {
  let bencher = @bench.Bench()
  for
    limbs in [
      768, 896, 1024, 1152, 1280, 1536, 1792, 2048, 2304, 2560, 2816, 3072,
    ] {
    let value = bin_coeff_autotune_pattern(limbs, 9)
    bin_coeff_autotune_bench(bencher, "specialized", "square", limbs, fn() {
      bencher.keep(bin_coeff_square_schoolbook(value))
    })
    bin_coeff_autotune_bench(bencher, "toom3", "square", limbs, fn() {
      bencher.keep(bin_coeff_mul_toom3(value, value))
    })
    if bin_coeff_ntt_fits(value, value) {
      bin_coeff_autotune_bench(bencher, "ntt", "square", limbs, fn() {
        bencher.keep(bin_coeff_square_ntt(value))
      })
    }
  }
  println("BIN_COEFF_AUTOTUNE_JSON=" + bencher.dump_summaries())
}
