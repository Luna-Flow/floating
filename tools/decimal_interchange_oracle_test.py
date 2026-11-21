"""Tests of `decimal_interchange_oracle.py`: known words of IEEE 754-2019 and of the DPD table."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

import decimal_interchange_oracle as oracle

ROOT = Path(__file__).resolve().parents[1]


class DeclettTest(unittest.TestCase):
    def test_known_declets(self) -> None:
        self.assertEqual(oracle.encode_declet((3, 4, 5)), 0x1C5)
        self.assertEqual(oracle.encode_declet((0, 1, 2)), 0x012)
        self.assertEqual(oracle.encode_declet((9, 9, 9)), 0x0FF)
        self.assertEqual(oracle.encode_declet((0, 0, 0)), 0x000)

    def test_all_thousand_declets_are_distinct_and_round_trip(self) -> None:
        seen = set()
        for n in range(1000):
            digits = (n // 100, n // 10 % 10, n % 10)
            code = oracle.encode_declet(digits)
            self.assertLess(code, 1024)
            self.assertNotIn(code, seen)
            seen.add(code)
            self.assertEqual(oracle.decode_declet(code), digits)
        self.assertEqual(len(seen), 1000)  # 24 of the 1024 codes are redundant


class RedundantTest(unittest.TestCase):
    def test_redundant_codes_decode_as_their_canonical_code(self) -> None:
        canonical = {oracle.encode_declet((n // 100, n // 10 % 10, n % 10)) for n in range(1000)}
        redundant = [c for c in range(1024) if c not in canonical]
        self.assertEqual(len(redundant), 24)
        for code in redundant:
            self.assertEqual(oracle.decode_declet(code), oracle.decode_declet(code & 0b0011111111))
        self.assertEqual(oracle.decode_declet(0x3FF), (9, 9, 9))

    def test_noncanonical_word_of_the_decimal32_witness(self) -> None:
        # #77FFFF3F: the declet 0x3FF is redundant; the value is 9999879E+90 and the canonical word #77F3FF3F
        fmt = oracle.DECIMAL32
        self.assertEqual(oracle.decode_finite(0x77FFFF3F, fmt), (False, 9999879, 90))
        self.assertEqual(oracle.hex_word(oracle.encode_finite(False, 9999879, 90, fmt), fmt), "#77F3FF3F")


class WordTest(unittest.TestCase):
    def test_words_of_the_vector_files(self) -> None:
        # the cases of testdata/decimal/ieee/decimal*_dpd.json that are finite, written by hand there
        for name in ("decimal32", "decimal64", "decimal128"):
            fmt = oracle.FORMATS[name]
            data = json.loads((ROOT / f"testdata/decimal/ieee/{name}_dpd.json").read_text())
            for case in data["cases"]:
                if case["class"] == "finite":
                    word = oracle.encode_finite(case["negative"], int(case["coefficient"]), case["exponent"], fmt)
                    self.assertEqual(oracle.hex_word(word, fmt), "#" + case["canonical"], case["id"])
                    self.assertEqual(
                        oracle.decode_finite(word, fmt), (case["negative"], int(case["coefficient"]), case["exponent"])
                    )
                elif case["class"] == "infinity":
                    self.assertEqual(
                        oracle.hex_word(oracle.encode_infinity(case["negative"], fmt), fmt), "#" + case["canonical"]
                    )
                elif case["class"] in ("qnan", "snan"):
                    word = oracle.encode_nan(case["negative"], case["class"] == "snan", int(case["payload"]), fmt)
                    self.assertEqual(oracle.hex_word(word, fmt), "#" + case["canonical"], case["id"])

    def test_largest_values(self) -> None:
        self.assertEqual(
            oracle.hex_word(oracle.encode_finite(False, 9999999, 90, oracle.DECIMAL32), oracle.DECIMAL32), "#77F3FCFF"
        )
        self.assertEqual(
            oracle.hex_word(oracle.encode_finite(False, 10**16 - 1, 369, oracle.DECIMAL64), oracle.DECIMAL64),
            "#77FCFF3FCFF3FCFF",
        )

    def test_nan_payload(self) -> None:
        self.assertEqual(oracle.hex_word(oracle.encode_nan(False, False, 12345, oracle.DECIMAL32), oracle.DECIMAL32), "#7C0049C5")
        self.assertEqual(oracle.hex_word(oracle.encode_nan(True, True, 12345, oracle.DECIMAL32), oracle.DECIMAL32), "#FE0049C5")


class RoundTest(unittest.TestCase):
    def test_exact_value_has_no_flags(self) -> None:
        self.assertEqual(oracle.round_to_format(False, 123, 88, oracle.DECIMAL32), ("finite", 123, 88, set()))

    def test_clamp_pads_the_coefficient(self) -> None:
        self.assertEqual(oracle.round_to_format(False, 123, 94, oracle.DECIMAL32)[:3], ("finite", 1230000, 90))

    def test_rounding_to_seven_digits_ties_to_even(self) -> None:
        self.assertEqual(
            oracle.round_to_format(False, 12345678, 0, oracle.DECIMAL32), ("finite", 1234568, 1, {"inexact"})
        )
        self.assertEqual(oracle.round_to_format(False, 12345685, 0, oracle.DECIMAL32)[:3], ("finite", 1234568, 1))
        self.assertEqual(oracle.round_to_format(False, 12345675, 0, oracle.DECIMAL32)[:3], ("finite", 1234568, 1))

    def test_carry_after_rounding(self) -> None:
        self.assertEqual(oracle.round_to_format(False, 99999995, 0, oracle.DECIMAL32)[:3], ("finite", 1000000, 2))

    def test_overflow_and_underflow(self) -> None:
        self.assertEqual(oracle.round_to_format(False, 1, 97, oracle.DECIMAL32)[0], "inf")
        kind, c, e, flags = oracle.round_to_format(False, 1, -102, oracle.DECIMAL32)
        self.assertEqual((kind, c, e), ("finite", 0, -101))
        self.assertEqual(flags, {"inexact", "underflow"})


if __name__ == "__main__":
    unittest.main()
