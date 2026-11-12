import json
import unittest

import generate_decimal_total_order as total_order
from generate_decimal_total_order import Operand


def finite(text: str) -> Operand:
    negative = text.startswith("-")
    coefficient, exponent = text.lstrip("-").split("E")
    return Operand(negative, "finite", int(coefficient), int(exponent))


def nan(negative: bool, signaling: bool, payload: int = 0) -> Operand:
    return Operand(negative, "snan" if signaling else "qnan", payload)


class DecimalTotalOrderTests(unittest.TestCase):
    def test_numeric_order_and_signed_zeros(self) -> None:
        # §5.10 a), b), c) 1), c) 2)
        self.assertTrue(total_order.total_order(finite("-5E-1"), finite("1E+0")))
        self.assertFalse(total_order.total_order(finite("1E+0"), finite("-5E-1")))
        self.assertTrue(total_order.total_order(finite("-0E+0"), finite("0E+0")))
        self.assertFalse(total_order.total_order(finite("0E+0"), finite("-0E+0")))

    def test_cohort_members_order_by_exponent(self) -> None:
        # §5.10 c) 3): 1.00 (100E-2) orders below 1 (1E+0); reversed for a negative sign
        self.assertTrue(total_order.total_order(finite("100E-2"), finite("1E+0")))
        self.assertFalse(total_order.total_order(finite("1E+0"), finite("100E-2")))
        self.assertTrue(total_order.total_order(finite("-1E+0"), finite("-100E-2")))
        self.assertTrue(total_order.total_order(finite("-0E+5"), finite("-0E-5")))

    def test_nan_positions(self) -> None:
        # §5.10 d): -qNaN < -sNaN < numbers < +sNaN < +qNaN
        chain = [
            nan(True, False),
            nan(True, True),
            Operand(True, "infinity"),
            finite("0E+0"),
            Operand(False, "infinity"),
            nan(False, True),
            nan(False, False),
        ]
        for lower, higher in zip(chain, chain[1:]):
            self.assertEqual(total_order.compare(lower, higher), -1, (lower, higher))
            self.assertEqual(total_order.compare(higher, lower), 1, (lower, higher))

    def test_checked_in_corpus_is_current(self) -> None:
        checked_in = json.loads(total_order.FIXTURE_PATH.read_text(encoding="utf-8"))
        self.assertEqual(checked_in, total_order.fixture())
        self.assertEqual(total_order.pair_count(checked_in), 18816)


if __name__ == "__main__":
    unittest.main()
