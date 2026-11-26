import unittest

import interval_reverse_oracle as oracle


class IntervalReverseOracleTest(unittest.TestCase):
    def test_table_is_current(self) -> None:
        self.assertEqual(oracle.TABLE.read_text(encoding="utf-8"), oracle.build())

    def test_known_rows(self) -> None:
        # 2^(1/3) at 8 bits is 1.25992..: between 1.0100001b and 1.0100010b (80/64 and 81/64 are 1.25 and 1.265625)
        lo, hi = oracle.ends_p1((3, 0), (2, 0), 8)
        self.assertEqual((oracle.hexa(lo), oracle.hexa(hi)), ("0xa1p-7", "0x51p-6"))
        # ln 4 / ln 8 = 2/3 at 3 bits: between 0.101b (5/8 = 0.625) and 0.110b (3/4)
        lo, hi = oracle.ends_p2((8, 0), (4, 0), 3)
        self.assertEqual((oracle.hexa(lo), oracle.hexa(hi)), ("0x5p-3", "0x3p-2"))
        # ln(1/2) / ln 8 = -1/3 at 3 bits: between -0.011b (-3/8) and -0.0101b (-5/16, 3 bits)
        lo, hi = oracle.ends_p2((8, 0), (1, -1), 3)
        self.assertEqual((oracle.hexa(lo), oracle.hexa(hi)), ("-0x3p-3", "-0x5p-4"))


if __name__ == "__main__":
    unittest.main()
