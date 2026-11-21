///|
// oracle: A
// source: Etiny = Emin - precision + 1 and Etop = Emax - digits + 1 (GDA 1.70, Context): 30 etiny rows and 16 etop rows, 30 etiny rows and 16 etop
//   rows written out as integers computed with Python
// shares: nothing
test "etiny and etop equal the exponent bounds they replace" {
  let etiny_rows : Array[(Int32, Int32, Int32)] = [
    (1, 0, 0),
    (1, -1, -1),
    (1, -101, -101),
    (1, -6_176, -6_176),
    (1, -999_999_999, -999_999_999),
    (2, 0, -1),
    (2, -1, -2),
    (2, -101, -102),
    (2, -6_176, -6_177),
    (2, -999_999_999, -1_000_000_000),
    (7, 0, -6),
    (7, -1, -7),
    (7, -101, -107),
    (7, -6_176, -6_182),
    (7, -999_999_999, -1_000_000_005),
    (16, 0, -15),
    (16, -1, -16),
    (16, -101, -116),
    (16, -6_176, -6_191),
    (16, -999_999_999, -1_000_000_014),
    (34, 0, -33),
    (34, -1, -34),
    (34, -101, -134),
    (34, -6_176, -6_209),
    (34, -999_999_999, -1_000_000_032),
    (999_999_999, 0, -999_999_998),
    (999_999_999, -1, -999_999_999),
    (999_999_999, -101, -1_000_000_099),
    (999_999_999, -6_176, -1_000_006_174),
    (999_999_999, -999_999_999, -1_999_999_997),
  ]
  let etop_rows : Array[(Int32, Int32, Int32)] = [
    (0, 1, 0),
    (0, 5, -4),
    (0, 40, -39),
    (0, 999_999_999, -999_999_998),
    (96, 1, 96),
    (96, 5, 92),
    (96, 40, 57),
    (96, 999_999_999, -999_999_902),
    (6_144, 1, 6_144),
    (6_144, 5, 6_140),
    (6_144, 40, 6_105),
    (6_144, 999_999_999, -999_993_854),
    (999_999_999, 1, 999_999_999),
    (999_999_999, 5, 999_999_995),
    (999_999_999, 40, 999_999_960),
    (999_999_999, 999_999_999, 1),
  ]
  let mut built = 0
  for row in etiny_rows {
    let (precision, e_min, expected) = row
    match
      DecimalContext::try_new(
        precision~,
        e_min~,
        e_max=999_999_999,
        extended=true,
      ) {
      Ok(ctx) => {
        assert_eq(etiny(ctx), expected)
        built += 1
      }
      Err(_) => ()
    }
  }
  for row in etop_rows {
    let (e_max, digits, expected) = row
    match
      DecimalContext::try_new(precision=7, e_min=-101, e_max~, extended=true) {
      Ok(ctx) => {
        assert_eq(etop(ctx, digits), expected)
        built += 1
      }
      Err(_) => ()
    }
  }
  assert_eq(built, 46)
}
