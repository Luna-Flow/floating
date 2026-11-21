///|
// oracle-file: A
// producer: tools/generate_interchange_rows.py with tools/decimal_interchange_oracle.py (the layout of IEEE 754-2019 3.5.2 in
//   Python, checked against testdata/decimal/ieee/decimal*_dpd.json; rounding to the format by Python integers)
// input: per format 29 finite values (exact, clamped, largest, smallest, zeros, more digits than the format with the ties and a
//   carry, overflow, underflow), both signs, quiet and signaling NaN with payloads 0, 12345, 54321, infinities
// Columns: decimal text, format, expected word, inexact, overflow, underflow.
// library-ran: no

///|
fn interchange_rows() -> Array[(String, String, String, Bool, Bool, Bool)] {
  [
    ("1E0", "decimal32", "#22500001", false, false, false),
    ("-1E0", "decimal32", "#A2500001", false, false, false),
    ("750E-2", "decimal32", "#223003D0", false, false, false),
    ("-750E-2", "decimal32", "#A23003D0", false, false, false),
    ("123E94", "decimal32", "#47F4C000", false, false, false),
    ("-123E94", "decimal32", "#C7F4C000", false, false, false),
    ("123E86", "decimal32", "#43B000A3", false, false, false),
    ("-123E86", "decimal32", "#C3B000A3", false, false, false),
    ("9999999E90", "decimal32", "#77F3FCFF", false, false, false),
    ("-9999999E90", "decimal32", "#F7F3FCFF", false, false, false),
    ("1E90", "decimal32", "#43F00001", false, false, false),
    ("-1E90", "decimal32", "#C3F00001", false, false, false),
    ("1E-95", "decimal32", "#00600001", false, false, false),
    ("-1E-95", "decimal32", "#80600001", false, false, false),
    ("1E-101", "decimal32", "#00000001", false, false, false),
    ("-1E-101", "decimal32", "#80000001", false, false, false),
    ("9999999E-101", "decimal32", "#6403FCFF", false, false, false),
    ("-9999999E-101", "decimal32", "#E403FCFF", false, false, false),
    ("0E0", "decimal32", "#22500000", false, false, false),
    ("-0E0", "decimal32", "#A2500000", false, false, false),
    ("0E-101", "decimal32", "#00000000", false, false, false),
    ("-0E-101", "decimal32", "#80000000", false, false, false),
    ("0E93", "decimal32", "#43F00000", false, false, false),
    ("-0E93", "decimal32", "#C3F00000", false, false, false),
    ("5E0", "decimal32", "#22500005", false, false, false),
    ("-5E0", "decimal32", "#A2500005", false, false, false),
    ("11111111E0", "decimal32", "#26624491", true, false, false),
    ("-11111111E0", "decimal32", "#A6624491", true, false, false),
    ("11111114E0", "decimal32", "#26624491", true, false, false),
    ("-11111114E0", "decimal32", "#A6624491", true, false, false),
    ("11111125E0", "decimal32", "#26624492", true, false, false),
    ("-11111125E0", "decimal32", "#A6624492", true, false, false),
    ("11111135E0", "decimal32", "#26624494", true, false, false),
    ("-11111135E0", "decimal32", "#A6624494", true, false, false),
    ("11111116E0", "decimal32", "#26624492", true, false, false),
    ("-11111116E0", "decimal32", "#A6624492", true, false, false),
    ("99999995E0", "decimal32", "#26700000", true, false, false),
    ("-99999995E0", "decimal32", "#A6700000", true, false, false),
    ("99999994E0", "decimal32", "#6E63FCFF", true, false, false),
    ("-99999994E0", "decimal32", "#EE63FCFF", true, false, false),
    ("1E97", "decimal32", "#78000000", true, true, false),
    ("-1E97", "decimal32", "#F8000000", true, true, false),
    ("99999995E90", "decimal32", "#78000000", true, true, false),
    ("-99999995E90", "decimal32", "#F8000000", true, true, false),
    ("9999999E91", "decimal32", "#78000000", true, true, false),
    ("-9999999E91", "decimal32", "#F8000000", true, true, false),
    ("1E-102", "decimal32", "#00000000", true, false, true),
    ("-1E-102", "decimal32", "#80000000", true, false, true),
    ("5E-102", "decimal32", "#00000000", true, false, true),
    ("-5E-102", "decimal32", "#80000000", true, false, true),
    ("6E-102", "decimal32", "#00000001", true, false, true),
    ("-6E-102", "decimal32", "#80000001", true, false, true),
    ("15E-102", "decimal32", "#00000002", true, false, true),
    ("-15E-102", "decimal32", "#80000002", true, false, true),
    ("25E-102", "decimal32", "#00000002", true, false, true),
    ("-25E-102", "decimal32", "#80000002", true, false, true),
    ("1E-106", "decimal32", "#00000000", true, false, true),
    ("-1E-106", "decimal32", "#80000000", true, false, true),
    ("NaN", "decimal32", "#7C000000", false, false, false),
    ("sNaN", "decimal32", "#7E000000", false, false, false),
    ("-NaN", "decimal32", "#FC000000", false, false, false),
    ("-sNaN", "decimal32", "#FE000000", false, false, false),
    ("NaN12345", "decimal32", "#7C0049C5", false, false, false),
    ("sNaN12345", "decimal32", "#7E0049C5", false, false, false),
    ("-NaN12345", "decimal32", "#FC0049C5", false, false, false),
    ("-sNaN12345", "decimal32", "#FE0049C5", false, false, false),
    ("NaN54321", "decimal32", "#7C0151A1", false, false, false),
    ("sNaN54321", "decimal32", "#7E0151A1", false, false, false),
    ("-NaN54321", "decimal32", "#FC0151A1", false, false, false),
    ("-sNaN54321", "decimal32", "#FE0151A1", false, false, false),
    ("Infinity", "decimal32", "#78000000", false, false, false),
    ("-Infinity", "decimal32", "#F8000000", false, false, false),
    ("1E0", "decimal64", "#2238000000000001", false, false, false),
    ("-1E0", "decimal64", "#A238000000000001", false, false, false),
    ("750E-2", "decimal64", "#22300000000003D0", false, false, false),
    ("-750E-2", "decimal64", "#A2300000000003D0", false, false, false),
    ("123E382", "decimal64", "#47FD300000000000", false, false, false),
    ("-123E382", "decimal64", "#C7FD300000000000", false, false, false),
    ("123E365", "decimal64", "#43EC0000000000A3", false, false, false),
    ("-123E365", "decimal64", "#C3EC0000000000A3", false, false, false),
    (
      "9999999999999999E369", "decimal64", "#77FCFF3FCFF3FCFF", false, false, false,
    ),
    (
      "-9999999999999999E369", "decimal64", "#F7FCFF3FCFF3FCFF", false, false, false,
    ),
    ("1E369", "decimal64", "#43FC000000000001", false, false, false),
    ("-1E369", "decimal64", "#C3FC000000000001", false, false, false),
    ("1E-383", "decimal64", "#003C000000000001", false, false, false),
    ("-1E-383", "decimal64", "#803C000000000001", false, false, false),
    ("1E-398", "decimal64", "#0000000000000001", false, false, false),
    ("-1E-398", "decimal64", "#8000000000000001", false, false, false),
    (
      "9999999999999999E-398", "decimal64", "#6400FF3FCFF3FCFF", false, false, false,
    ),
    (
      "-9999999999999999E-398", "decimal64", "#E400FF3FCFF3FCFF", false, false, false,
    ),
    ("0E0", "decimal64", "#2238000000000000", false, false, false),
    ("-0E0", "decimal64", "#A238000000000000", false, false, false),
    ("0E-398", "decimal64", "#0000000000000000", false, false, false),
    ("-0E-398", "decimal64", "#8000000000000000", false, false, false),
    ("0E372", "decimal64", "#43FC000000000000", false, false, false),
    ("-0E372", "decimal64", "#C3FC000000000000", false, false, false),
    ("5E0", "decimal64", "#2238000000000005", false, false, false),
    ("-5E0", "decimal64", "#A238000000000005", false, false, false),
    (
      "11111111111111111E0", "decimal64", "#263C912449124491", true, false, false,
    ),
    (
      "-11111111111111111E0", "decimal64", "#A63C912449124491", true, false, false,
    ),
    (
      "11111111111111114E0", "decimal64", "#263C912449124491", true, false, false,
    ),
    (
      "-11111111111111114E0", "decimal64", "#A63C912449124491", true, false, false,
    ),
    (
      "11111111111111125E0", "decimal64", "#263C912449124492", true, false, false,
    ),
    (
      "-11111111111111125E0", "decimal64", "#A63C912449124492", true, false, false,
    ),
    (
      "11111111111111135E0", "decimal64", "#263C912449124494", true, false, false,
    ),
    (
      "-11111111111111135E0", "decimal64", "#A63C912449124494", true, false, false,
    ),
    (
      "11111111111111116E0", "decimal64", "#263C912449124492", true, false, false,
    ),
    (
      "-11111111111111116E0", "decimal64", "#A63C912449124492", true, false, false,
    ),
    (
      "99999999999999995E0", "decimal64", "#2640000000000000", true, false, false,
    ),
    (
      "-99999999999999995E0", "decimal64", "#A640000000000000", true, false, false,
    ),
    (
      "99999999999999994E0", "decimal64", "#6E3CFF3FCFF3FCFF", true, false, false,
    ),
    (
      "-99999999999999994E0", "decimal64", "#EE3CFF3FCFF3FCFF", true, false, false,
    ),
    ("1E385", "decimal64", "#7800000000000000", true, true, false),
    ("-1E385", "decimal64", "#F800000000000000", true, true, false),
    (
      "99999999999999995E369", "decimal64", "#7800000000000000", true, true, false,
    ),
    (
      "-99999999999999995E369", "decimal64", "#F800000000000000", true, true, false,
    ),
    (
      "9999999999999999E370", "decimal64", "#7800000000000000", true, true, false,
    ),
    (
      "-9999999999999999E370", "decimal64", "#F800000000000000", true, true, false,
    ),
    ("1E-399", "decimal64", "#0000000000000000", true, false, true),
    ("-1E-399", "decimal64", "#8000000000000000", true, false, true),
    ("5E-399", "decimal64", "#0000000000000000", true, false, true),
    ("-5E-399", "decimal64", "#8000000000000000", true, false, true),
    ("6E-399", "decimal64", "#0000000000000001", true, false, true),
    ("-6E-399", "decimal64", "#8000000000000001", true, false, true),
    ("15E-399", "decimal64", "#0000000000000002", true, false, true),
    ("-15E-399", "decimal64", "#8000000000000002", true, false, true),
    ("25E-399", "decimal64", "#0000000000000002", true, false, true),
    ("-25E-399", "decimal64", "#8000000000000002", true, false, true),
    ("1E-403", "decimal64", "#0000000000000000", true, false, true),
    ("-1E-403", "decimal64", "#8000000000000000", true, false, true),
    ("NaN", "decimal64", "#7C00000000000000", false, false, false),
    ("sNaN", "decimal64", "#7E00000000000000", false, false, false),
    ("-NaN", "decimal64", "#FC00000000000000", false, false, false),
    ("-sNaN", "decimal64", "#FE00000000000000", false, false, false),
    ("NaN12345", "decimal64", "#7C000000000049C5", false, false, false),
    ("sNaN12345", "decimal64", "#7E000000000049C5", false, false, false),
    ("-NaN12345", "decimal64", "#FC000000000049C5", false, false, false),
    ("-sNaN12345", "decimal64", "#FE000000000049C5", false, false, false),
    ("NaN54321", "decimal64", "#7C000000000151A1", false, false, false),
    ("sNaN54321", "decimal64", "#7E000000000151A1", false, false, false),
    ("-NaN54321", "decimal64", "#FC000000000151A1", false, false, false),
    ("-sNaN54321", "decimal64", "#FE000000000151A1", false, false, false),
    ("Infinity", "decimal64", "#7800000000000000", false, false, false),
    ("-Infinity", "decimal64", "#F800000000000000", false, false, false),
    (
      "1E0", "decimal128", "#22080000000000000000000000000001", false, false, false,
    ),
    (
      "-1E0", "decimal128", "#A2080000000000000000000000000001", false, false, false,
    ),
    (
      "750E-2", "decimal128", "#220780000000000000000000000003D0", false, false,
      false,
    ),
    (
      "-750E-2", "decimal128", "#A20780000000000000000000000003D0", false, false,
      false,
    ),
    (
      "123E6142", "decimal128", "#47FFD300000000000000000000000000", false, false,
      false,
    ),
    (
      "-123E6142", "decimal128", "#C7FFD300000000000000000000000000", false, false,
      false,
    ),
    (
      "123E6107", "decimal128", "#43FEC0000000000000000000000000A3", false, false,
      false,
    ),
    (
      "-123E6107", "decimal128", "#C3FEC0000000000000000000000000A3", false, false,
      false,
    ),
    (
      "9999999999999999999999999999999999E6111", "decimal128", "#77FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF",
      false, false, false,
    ),
    (
      "-9999999999999999999999999999999999E6111", "decimal128", "#F7FFCFF3FCFF3FCFF3FCFF3FCFF3FCFF",
      false, false, false,
    ),
    (
      "1E6111", "decimal128", "#43FFC000000000000000000000000001", false, false,
      false,
    ),
    (
      "-1E6111", "decimal128", "#C3FFC000000000000000000000000001", false, false,
      false,
    ),
    (
      "1E-6143", "decimal128", "#00084000000000000000000000000001", false, false,
      false,
    ),
    (
      "-1E-6143", "decimal128", "#80084000000000000000000000000001", false, false,
      false,
    ),
    (
      "1E-6176", "decimal128", "#00000000000000000000000000000001", false, false,
      false,
    ),
    (
      "-1E-6176", "decimal128", "#80000000000000000000000000000001", false, false,
      false,
    ),
    (
      "9999999999999999999999999999999999E-6176", "decimal128", "#64000FF3FCFF3FCFF3FCFF3FCFF3FCFF",
      false, false, false,
    ),
    (
      "-9999999999999999999999999999999999E-6176", "decimal128", "#E4000FF3FCFF3FCFF3FCFF3FCFF3FCFF",
      false, false, false,
    ),
    (
      "0E0", "decimal128", "#22080000000000000000000000000000", false, false, false,
    ),
    (
      "-0E0", "decimal128", "#A2080000000000000000000000000000", false, false, false,
    ),
    (
      "0E-6176", "decimal128", "#00000000000000000000000000000000", false, false,
      false,
    ),
    (
      "-0E-6176", "decimal128", "#80000000000000000000000000000000", false, false,
      false,
    ),
    (
      "0E6114", "decimal128", "#43FFC000000000000000000000000000", false, false,
      false,
    ),
    (
      "-0E6114", "decimal128", "#C3FFC000000000000000000000000000", false, false,
      false,
    ),
    (
      "5E0", "decimal128", "#22080000000000000000000000000005", false, false, false,
    ),
    (
      "-5E0", "decimal128", "#A2080000000000000000000000000005", false, false, false,
    ),
    (
      "11111111111111111111111111111111111E0", "decimal128", "#26084912449124491244912449124491",
      true, false, false,
    ),
    (
      "-11111111111111111111111111111111111E0", "decimal128", "#A6084912449124491244912449124491",
      true, false, false,
    ),
    (
      "11111111111111111111111111111111114E0", "decimal128", "#26084912449124491244912449124491",
      true, false, false,
    ),
    (
      "-11111111111111111111111111111111114E0", "decimal128", "#A6084912449124491244912449124491",
      true, false, false,
    ),
    (
      "11111111111111111111111111111111125E0", "decimal128", "#26084912449124491244912449124492",
      true, false, false,
    ),
    (
      "-11111111111111111111111111111111125E0", "decimal128", "#A6084912449124491244912449124492",
      true, false, false,
    ),
    (
      "11111111111111111111111111111111135E0", "decimal128", "#26084912449124491244912449124494",
      true, false, false,
    ),
    (
      "-11111111111111111111111111111111135E0", "decimal128", "#A6084912449124491244912449124494",
      true, false, false,
    ),
    (
      "11111111111111111111111111111111116E0", "decimal128", "#26084912449124491244912449124492",
      true, false, false,
    ),
    (
      "-11111111111111111111111111111111116E0", "decimal128", "#A6084912449124491244912449124492",
      true, false, false,
    ),
    (
      "99999999999999999999999999999999995E0", "decimal128", "#26088000000000000000000000000000",
      true, false, false,
    ),
    (
      "-99999999999999999999999999999999995E0", "decimal128", "#A6088000000000000000000000000000",
      true, false, false,
    ),
    (
      "99999999999999999999999999999999994E0", "decimal128", "#6E084FF3FCFF3FCFF3FCFF3FCFF3FCFF",
      true, false, false,
    ),
    (
      "-99999999999999999999999999999999994E0", "decimal128", "#EE084FF3FCFF3FCFF3FCFF3FCFF3FCFF",
      true, false, false,
    ),
    (
      "1E6145", "decimal128", "#78000000000000000000000000000000", true, true, false,
    ),
    (
      "-1E6145", "decimal128", "#F8000000000000000000000000000000", true, true, false,
    ),
    (
      "99999999999999999999999999999999995E6111", "decimal128", "#78000000000000000000000000000000",
      true, true, false,
    ),
    (
      "-99999999999999999999999999999999995E6111", "decimal128", "#F8000000000000000000000000000000",
      true, true, false,
    ),
    (
      "9999999999999999999999999999999999E6112", "decimal128", "#78000000000000000000000000000000",
      true, true, false,
    ),
    (
      "-9999999999999999999999999999999999E6112", "decimal128", "#F8000000000000000000000000000000",
      true, true, false,
    ),
    (
      "1E-6177", "decimal128", "#00000000000000000000000000000000", true, false,
      true,
    ),
    (
      "-1E-6177", "decimal128", "#80000000000000000000000000000000", true, false,
      true,
    ),
    (
      "5E-6177", "decimal128", "#00000000000000000000000000000000", true, false,
      true,
    ),
    (
      "-5E-6177", "decimal128", "#80000000000000000000000000000000", true, false,
      true,
    ),
    (
      "6E-6177", "decimal128", "#00000000000000000000000000000001", true, false,
      true,
    ),
    (
      "-6E-6177", "decimal128", "#80000000000000000000000000000001", true, false,
      true,
    ),
    (
      "15E-6177", "decimal128", "#00000000000000000000000000000002", true, false,
      true,
    ),
    (
      "-15E-6177", "decimal128", "#80000000000000000000000000000002", true, false,
      true,
    ),
    (
      "25E-6177", "decimal128", "#00000000000000000000000000000002", true, false,
      true,
    ),
    (
      "-25E-6177", "decimal128", "#80000000000000000000000000000002", true, false,
      true,
    ),
    (
      "1E-6181", "decimal128", "#00000000000000000000000000000000", true, false,
      true,
    ),
    (
      "-1E-6181", "decimal128", "#80000000000000000000000000000000", true, false,
      true,
    ),
    (
      "NaN", "decimal128", "#7C000000000000000000000000000000", false, false, false,
    ),
    (
      "sNaN", "decimal128", "#7E000000000000000000000000000000", false, false, false,
    ),
    (
      "-NaN", "decimal128", "#FC000000000000000000000000000000", false, false, false,
    ),
    (
      "-sNaN", "decimal128", "#FE000000000000000000000000000000", false, false, false,
    ),
    (
      "NaN12345", "decimal128", "#7C0000000000000000000000000049C5", false, false,
      false,
    ),
    (
      "sNaN12345", "decimal128", "#7E0000000000000000000000000049C5", false, false,
      false,
    ),
    (
      "-NaN12345", "decimal128", "#FC0000000000000000000000000049C5", false, false,
      false,
    ),
    (
      "-sNaN12345", "decimal128", "#FE0000000000000000000000000049C5", false, false,
      false,
    ),
    (
      "NaN54321", "decimal128", "#7C0000000000000000000000000151A1", false, false,
      false,
    ),
    (
      "sNaN54321", "decimal128", "#7E0000000000000000000000000151A1", false, false,
      false,
    ),
    (
      "-NaN54321", "decimal128", "#FC0000000000000000000000000151A1", false, false,
      false,
    ),
    (
      "-sNaN54321", "decimal128", "#FE0000000000000000000000000151A1", false, false,
      false,
    ),
    (
      "Infinity", "decimal128", "#78000000000000000000000000000000", false, false,
      false,
    ),
    (
      "-Infinity", "decimal128", "#F8000000000000000000000000000000", false, false,
      false,
    ),
  ]
}
