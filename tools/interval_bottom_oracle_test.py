#!/usr/bin/env python3
"""Tests of the pure part of tools/interval_bottom_oracle.py."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import interval_bottom_oracle as o  # noqa: E402

E_MIN = o.E_MIN


class TextTest(unittest.TestCase):
    def test_canon_and_text(self) -> None:
        self.assertEqual(o.canon((12, 0)), (3, 2))
        self.assertEqual(o.canon((-8, 3)), (-1, 6))
        self.assertEqual(o.canon((0, 5)), (0, 0))
        self.assertEqual(o.text((12, 0)), "0x3p2")
        self.assertEqual(o.text((-1, -1073741872)), "-0x1p-1073741872")
        self.assertEqual(o.text((0, 9)), "0x0p0")

    def test_runs_round_trip(self) -> None:
        for n in (1, 255, (1 << 400) - 1, (3 << 4000) + 5, (0xFD << 120) + 1, 16**40 + 7):
            self.assertEqual(int(o.expand_hex(o.run_hex(n)), 16), n)
        self.assertEqual(o.run_hex(0x3 << 80), "3,0*20")
        self.assertEqual(o.run_hex((1 << 128) - 1), "f*32")

    def test_short_numbers_have_no_runs(self) -> None:
        self.assertNotIn("*", o.run_hex(0x123456789ABCDEF))


class RoundingTest(unittest.TestCase):
    def test_outward(self) -> None:
        # 2^-60 * 3 at 24 bits near the bottom: the grid quantum is 2^(E_MIN - 23)
        lo, hi = o.outward((1, E_MIN - 60), (3, E_MIN - 60), 24)
        self.assertEqual(o.canon(lo), (0, 0))
        self.assertEqual(hi, (1, E_MIN - 23))

    def test_mpr_issue_578(self) -> None:
        # the hull of the first case of the issue, worked out by hand with Fraction in the old test
        line = o.mpr_line((133022375522373997, -1073741877), (389, -1073741869), 53)
        fields = line.split()
        self.assertEqual(fields[4], o.text((4156949235071075, -1073741872)))
        self.assertEqual(fields[5], o.text((8313898470154599, -1073741873)))


class MidTest(unittest.TestCase):
    def test_issue_579(self) -> None:
        # [2^(e_min - 60), 3 * 2^(e_min - 60)] at 113 bits: mid 2^(e_min - 59), rad 2^(e_min - 60), wid 2^(e_min - 59)
        line = o.mid_line((1, E_MIN - 60), (3, E_MIN - 60), 113)
        self.assertEqual(line.split()[4:], [o.text((1, E_MIN - 59)), o.text((1, E_MIN - 60)), o.text((1, E_MIN - 59))])

    def test_tie_goes_to_even(self) -> None:
        # [0, 3 * 2^(e_min - 52)] at 53 bits: the centre 1.5 quanta is a tie, the even number is 2 quanta
        line = o.mid_line((0, 0), (3, E_MIN - 52), 53)
        self.assertEqual(line.split()[4], o.text((1, E_MIN - 51)))

    def test_ctx_rounds_once(self) -> None:
        # [1, 2^100000] at 200,000 bits: 2^99999 + 1/2 exactly
        self.assertEqual(o.mid_of((1, 0), (1, 100000), 53, 200000), o.canon(((1 << 100000) + 1, -1)))


class FmaTest(unittest.TestCase):
    def test_issue_607(self) -> None:
        t = (1, E_MIN - 3)
        line = o.fma_line(53, (t, t), ((1, 0), (1, 0)), (t, t))
        self.assertEqual(line.split()[-2:], [o.text((1, E_MIN - 2))] * 2)


class RowsTest(unittest.TestCase):
    def test_counts(self) -> None:
        rows = o.rows()
        kinds = [r.split()[0] for r in rows]
        self.assertEqual(kinds.count("mid"), 1630)
        self.assertEqual(kinds.count("mpr"), 3802)
        self.assertEqual(kinds.count("fma"), 1501)
        self.assertEqual(kinds.count("sum"), 800)
        self.assertEqual(kinds.count("ctx"), 505)


if __name__ == "__main__":
    unittest.main()
