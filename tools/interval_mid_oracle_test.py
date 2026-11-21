import unittest

import interval_mid_oracle as oracle


class IntervalMidOracleTest(unittest.TestCase):
    def test_table_is_current(self) -> None:
        self.assertEqual(oracle.TABLE.read_text(encoding="utf-8"), oracle.build())

    def test_known_rows(self) -> None:
        # [-1, 2]: mid 1/2, rad 3/2
        m, r = oracle.mid_rad((-1, 0), (2, 0), 53)
        self.assertEqual((oracle.fmt(m), oracle.fmt(r)), ("1p-1", "3p-1"))
        # one unit apart at 3 bits: [7, 8] has the midpoint 7.5, a tie between 7 and 8 at 3 bits, even is 8
        m, r = oracle.mid_rad((7, 0), (8, 0), 3)
        self.assertEqual((oracle.fmt(m), oracle.fmt(r)), ("1p3", "1p0"))
        # a point
        m, r = oracle.mid_rad((5, -2), (5, -2), 8)
        self.assertEqual((oracle.fmt(m), oracle.fmt(r)), ("5p-2", "0"))


if __name__ == "__main__":
    unittest.main()
