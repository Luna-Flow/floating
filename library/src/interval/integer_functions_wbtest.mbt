///|
fn int_fn_box(lo : Double, hi : Double) -> Interval {
  Interval::from_bounds(
    @binary.Binary::from_double(lo),
    @binary.Binary::from_double(hi),
  )
}

///|
fn int_fn_apply(name : String, x : Interval) -> Interval {
  match name {
    "sign" => x.sign()
    "ceil" => x.ceil()
    "floor" => x.floor()
    "trunc" => x.trunc()
    "even" => x.round_ties_to_even()
    "away" => x.round_ties_to_away()
    _ => abort("unknown integer function " + name)
  }
}

///|
fn int_fn_apply_decorated(
  name : String,
  x : DecoratedInterval,
) -> DecoratedInterval {
  match name {
    "sign" => x.sign()
    "ceil" => x.ceil()
    "floor" => x.floor()
    "trunc" => x.trunc()
    "even" => x.round_ties_to_even()
    "away" => x.round_ties_to_away()
    _ => abort("unknown integer function " + name)
  }
}

///|
/// Expected values come from the definitions of IEEE 1788-2015 Table 9.1
/// (footnotes h, i, j) and 11.2, not from the implementation: the result is
/// `[f(lo), f(hi)]`; the decoration of a `com` input is `def` when `f` is not
/// constant on the box, `dac` when it is constant but a point of discontinuity
/// of `f` on the real line lies in the box, and `com` otherwise.
test "integer functions: bounds and decorations at each position of a jump" {
  // (function, lo, hi, result lo, result hi, decoration of the result)
  let cases : Array[(String, Double, Double, Double, Double, Decoration)] = [
    // ceil: jumps at the integers, ceil(n) = n (left-continuous)
    ("ceil", 1.0, 1.5, 1.0, 2.0, Def), // jump as lower endpoint
    ("ceil", 0.5, 1.0, 1.0, 1.0, Dac), // jump as upper endpoint
    ("ceil", 1.0, 1.0, 1.0, 1.0, Dac), // jump as a point box
    ("ceil", 0.5, 1.5, 1.0, 2.0, Def), // jump in the interior
    ("ceil", 1.5, 1.5, 2.0, 2.0, Com), // no jump point in the box
    ("ceil", 1.25, 1.75, 2.0, 2.0, Com),
    ("ceil", -1.1, 0.0, -1.0, 0.0, Def),
    // floor: jumps at the integers, floor(n) = n (right-continuous)
    ("floor", 1.0, 1.5, 1.0, 1.0, Dac),
    ("floor", 0.5, 1.0, 0.0, 1.0, Def),
    ("floor", 1.0, 1.0, 1.0, 1.0, Dac),
    ("floor", 0.5, 1.5, 0.0, 1.0, Def),
    ("floor", -1.2, -1.1, -2.0, -2.0, Com),
    // trunc: jumps at the nonzero integers; toward zero
    ("trunc", 1.0, 1.5, 1.0, 1.0, Dac),
    ("trunc", 0.5, 1.0, 0.0, 1.0, Def),
    ("trunc", 1.0, 1.0, 1.0, 1.0, Dac),
    ("trunc", 0.5, 1.5, 0.0, 1.0, Def),
    ("trunc", -1.5, -1.0, -1.0, -1.0, Dac), // negative: left-continuous
    ("trunc", -1.0, -0.5, -1.0, 0.0, Def),
    ("trunc", -1.0, -1.0, -1.0, -1.0, Dac),
    ("trunc", -1.5, 0.5, -1.0, 0.0, Def),
    ("trunc", -0.5, 0.5, 0.0, 0.0, Com), // 0 is not a jump of trunc
    ("trunc", 0.0, 0.0, 0.0, 0.0, Com),
    // sign: jump at 0
    ("sign", 0.0, 2.0, 0.0, 1.0, Def),
    ("sign", -2.0, 0.0, -1.0, 0.0, Def),
    ("sign", 0.0, 0.0, 0.0, 0.0, Dac),
    ("sign", -1.0, 1.0, -1.0, 1.0, Def),
    ("sign", 1.0, 2.0, 1.0, 1.0, Com),
    ("sign", -2.0, -1.0, -1.0, -1.0, Com),
    // roundTiesToEven: jumps at n + 1/2; 0.5 goes to 0, 1.5 to 2
    ("even", 0.5, 1.0, 0.0, 1.0, Def),
    ("even", 0.0, 0.5, 0.0, 0.0, Dac),
    ("even", 0.5, 0.5, 0.0, 0.0, Dac),
    ("even", 0.25, 0.75, 0.0, 1.0, Def),
    ("even", 1.5, 1.75, 2.0, 2.0, Dac),
    ("even", 1.0, 1.5, 1.0, 2.0, Def),
    ("even", 1.5, 1.5, 2.0, 2.0, Dac),
    ("even", 1.25, 1.75, 1.0, 2.0, Def),
    ("even", 0.25, 0.25, 0.0, 0.0, Com),
    ("even", 2.5, 2.5, 2.0, 2.0, Dac),
    ("even", 2.25, 2.75, 2.0, 3.0, Def),
    // roundTiesToAway: jumps at n + 1/2; 0.5 goes to 1, -0.5 to -1
    ("away", 0.5, 0.75, 1.0, 1.0, Dac),
    ("away", 0.25, 0.5, 0.0, 1.0, Def),
    ("away", 0.5, 0.5, 1.0, 1.0, Dac),
    ("away", 0.25, 0.75, 0.0, 1.0, Def),
    ("away", -0.5, -0.25, -1.0, 0.0, Def),
    ("away", -0.75, -0.5, -1.0, -1.0, Dac),
    ("away", -0.5, -0.5, -1.0, -1.0, Dac),
    ("away", -0.75, -0.25, -1.0, 0.0, Def),
    ("away", 2.5, 2.5, 3.0, 3.0, Dac),
    ("away", 2.25, 2.25, 2.0, 2.0, Com),
  ]
  for c in cases {
    let (name, lo, hi, rlo, rhi, dec) = c
    let x = int_fn_box(lo, hi)
    let expected = int_fn_box(rlo, rhi)
    let label = "\{name} [\{lo}, \{hi}]"
    let bare = int_fn_apply(name, x)
    assert_true(bare.identical(expected.with_precision(53)), msg=label)
    let got = int_fn_apply_decorated(name, DecoratedInterval::new(x))
    assert_true(got.interval() == expected, msg=label)
    assert_eq(got.decoration(), dec, msg=label)
  }
}

///|
test "integer functions: the input decoration caps the result (min-rule), NaI and empty" {
  for name in ["sign", "ceil", "floor", "trunc", "even", "away"] {
    let x = int_fn_box(0.25, 0.25)
    let weak = int_fn_apply_decorated(
      name,
      DecoratedInterval::new(x, decoration=Def),
    )
    assert_true(weak.decoration() == Def, msg=name)
    let trivial = int_fn_apply_decorated(
      name,
      DecoratedInterval::new(x, decoration=Trv),
    )
    assert_true(trivial.decoration() == Trv, msg=name)
    assert_true(int_fn_apply_decorated(name, DecoratedInterval::nai()).is_nai())
    let empty = int_fn_apply_decorated(
      name,
      DecoratedInterval::new(Interval::empty()),
    )
    assert_true(empty.is_empty(), msg=name)
    assert_eq(empty.decoration(), Trv, msg=name)
    assert_true(int_fn_apply(name, Interval::empty()).is_empty(), msg=name)
  }
}

///|
test "integer functions: unbounded boxes" {
  let inf = @binary.Binary::inf(precision=53)
  let ninf = @binary.Binary::inf(negative=true, precision=53)
  let one = @binary.Binary::from_int(1)
  let minus_one = @binary.Binary::from_int(-1)
  let up = Interval::from_bounds(one, inf)
  let down = Interval::from_bounds(ninf, minus_one)
  // sign is constant on a half line not containing 0, but the box is unbounded
  assert_true(up.sign() == int_fn_box(1.0, 1.0))
  assert_true(down.sign() == int_fn_box(-1.0, -1.0))
  assert_eq(DecoratedInterval::new(up, decoration=Dac).sign().decoration(), Dac)
  assert_eq(
    DecoratedInterval::new(down, decoration=Dac).sign().decoration(),
    Dac,
  )
  // ceil of [1, +inf) is [1, +inf), not continuous on the box: def
  assert_true(up.ceil() == up)
  assert_eq(DecoratedInterval::new(up, decoration=Dac).ceil().decoration(), Def)
  let entire = Interval::entire()
  assert_true(entire.floor() == entire)
  assert_true(entire.sign() == int_fn_box(-1.0, 1.0))
}

///|
test "integer functions: results are exact at a large precision and zero bounds are +0" {
  let x = Interval::from_bounds(
    @binary.Binary::from_double(-0.5, precision=200),
    @binary.Binary::from_double(-0.25, precision=200),
    precision=200,
  )
  let r = x.ceil()
  assert_true(r.upper_bound().is_zero())
  assert_false(r.upper_bound().is_negative())
  assert_eq(r.precision(), 200)
}
