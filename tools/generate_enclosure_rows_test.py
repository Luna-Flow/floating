from __future__ import annotations

import unittest
from fractions import Fraction

import generate_enclosure_rows as gen


class EnclosureRowsTest(unittest.TestCase):
    def test_parse_requests_skips_comments_and_checks_the_operation(self) -> None:
        self.assertEqual(gen.parse_requests("# c\n\nexp 0x1p0 64\n"), [("exp", "0x1p0", 64)])
        with self.assertRaises(ValueError):
            gen.parse_requests("sqrt 0x1p0 64\n")

    def test_hex_value(self) -> None:
        self.assertEqual(gen.hex_value("-0x3p-2"), Fraction(-3, 4))

    def test_gap_exponent(self) -> None:
        self.assertEqual(gen.gap_exponent("0x1p0", "0x1p0"), "")
        self.assertEqual(gen.gap_exponent("0x1p0", "0x9p-3"), "-3")
        self.assertEqual(gen.gap_exponent("-0x1p0", "-0x7p-3"), "-3")
        with self.assertRaises(ValueError):
            gen.gap_exponent("0x1p0", "0x3p0")

    def test_input_lines_pair_downward_and_upward(self) -> None:
        lines = gen.input_lines([("ln", "0x2p0", 80)])
        self.assertEqual([line.split()[2] for line in lines], ["d", "u"])
        self.assertTrue(all(line.split()[3] == "80" for line in lines))


if __name__ == "__main__":
    unittest.main()
