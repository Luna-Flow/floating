"""The words written out in `library/src/decimal/interchange_wbtest.mbt`, asserted with the two
independent encoders: `decimal_bid_oracle.py` (BID) and `decimal_interchange_oracle.py` (DPD)."""

import unittest
from decimal import ROUND_HALF_EVEN, Context, Decimal, Inexact, Underflow

import decimal_bid_oracle as bid
import decimal_interchange_oracle as dpd
from decimal_bid_oracle import Datum
from decimal_interchange_oracle import DECIMAL32, DECIMAL64, DECIMAL128


def bid_hex(fmt: dpd.Format, datum: Datum) -> str:
    return dpd.hex_word(bid.encode(fmt, datum), fmt)


def bid_read(fmt: dpd.Format, text: str) -> Datum:
    return bid.decode(fmt, int(text.lstrip("#"), 16))


class DeclettTest(unittest.TestCase):
    def test_1000_canonical_declets_round_trip_and_24_patterns_are_not_canonical(self) -> None:
        canonical = set()
        for value in range(1000):
            digits = (value // 100, value // 10 % 10, value % 10)
            code = dpd.encode_declet(digits)
            self.assertEqual(dpd.decode_declet(code), digits)
            canonical.add(code)
        self.assertEqual(len(canonical), 1000)
        self.assertEqual(1024 - len(canonical), 24)
        for code in range(1024):
            self.assertTrue(all(0 <= digit <= 9 for digit in dpd.decode_declet(code)))
            if code not in canonical:  # the form 01x11x111x, 10x11x111x or 11x11x111x of 3.5.2
                bits = f"{code:010b}"
                self.assertEqual((bits[3:5], bits[6:9]), ("11", "111"))
                self.assertIn(bits[:2], ("01", "10", "11"))


class BidTest(unittest.TestCase):
    def test_canonical_vectors(self) -> None:
        self.assertEqual(bid_hex(DECIMAL32, Datum(0, "finite", 0, 0)), "#32800000")
        self.assertEqual(bid_hex(DECIMAL32, Datum(0, "finite", 9999999, 0)), "#6CB8967F")
        self.assertEqual(bid_hex(DECIMAL64, Datum(0, "finite", 0, 0)), "#31C0000000000000")
        self.assertEqual(bid_hex(DECIMAL64, Datum(0, "finite", 9999999999999999, 0)), "#6C7386F26FC0FFFF")
        self.assertEqual(bid_hex(DECIMAL128, Datum(0, "finite", 0, 0)), "#30400000000000000000000000000000")

    def test_non_canonical_coefficient_is_zero(self) -> None:
        self.assertEqual(bid_read(DECIMAL32, "#6CB89680").coefficient, 0)

    def test_zero_witnesses(self) -> None:
        for fmt, text in [(DECIMAL32, "#32800000"), (DECIMAL64, "#31C0000000000000"), (DECIMAL128, "#30400000000000000000000000000000")]:
            self.assertEqual(bid_read(fmt, text), Datum(0, "finite", 0, 0))
        self.assertEqual(bid_read(DECIMAL64, "#0000000000000000"), Datum(0, "finite", 0, -398))


class NanTest(unittest.TestCase):
    def test_payloads_are_integers_across_formats(self) -> None:
        self.assertEqual(bid_read(DECIMAL32, "#7C000100"), Datum(0, "qnan", 256, 0))
        self.assertEqual(bid_hex(DECIMAL128, Datum(0, "qnan", 256, 0)), "#7C000000000000000000000000000100")
        self.assertEqual(bid_read(DECIMAL128, "#7C000000000000000000000000000100"), Datum(0, "qnan", 256, 0))
        self.assertEqual(bid_hex(DECIMAL32, Datum(0, "qnan", 256, 0)), "#7C000100")

    def test_wide_payload_keeps_its_low_digits_in_a_narrower_format(self) -> None:
        wide = bid_read(DECIMAL128, "#7C0000033B2E3C9FD0803CE800000000")
        self.assertEqual(wide.coefficient, 256000000000000000000000000000)
        # the reduction to the low p - 1 digits is the library's convention, applied here by hand
        self.assertEqual(bid_hex(DECIMAL32, Datum(0, "qnan", wide.coefficient % 10**6, 0)), "#7C000000")

    def test_non_canonical_payload_is_zero(self) -> None:
        datum = bid_read(DECIMAL64, "#7C03FFFFFFFFFFFF")
        self.assertEqual(datum.coefficient, 0)
        self.assertEqual(bid_hex(DECIMAL64, datum), "#7C00000000000000")

    def test_quiet_nan_with_payload_123(self) -> None:
        self.assertEqual(bid_hex(DECIMAL64, Datum(0, "qnan", 123, 0)), "#7C0000000000007B")

    def test_signaling_nan_payload_and_its_quiet_form(self) -> None:
        snan = bid_read(DECIMAL64, "#FF777D7CFFFFDFF7")
        self.assertEqual(snan, Datum(1, "snan", 982400754507767, 0))
        self.assertEqual(bid_hex(DECIMAL64, snan._replace(kind="qnan")), "#FC037D7CFFFFDFF7")

    def test_propagation_vectors(self) -> None:
        self.assertEqual(bid_read(DECIMAL32, "#7C8F423F"), Datum(0, "qnan", 999999, 0))
        self.assertEqual(bid_read(DECIMAL32, "#7E100000"), Datum(0, "snan", 0, 0))  # 0x100000 >= 10^6 is non-canonical
        self.assertEqual(bid_hex(DECIMAL32, Datum(0, "qnan", 999999, 0)), "#7C0F423F")
        self.assertEqual(bid_hex(DECIMAL32, Datum(0, "qnan", 0, 0)), "#7C000000")

    def test_negative_infinity_vector(self) -> None:
        datum = bid_read(DECIMAL64, "#FBFDFFDFFDFFF6FF")
        self.assertEqual((datum.sign, datum.kind), (1, "inf"))

    def test_special_witnesses_in_both_encodings(self) -> None:
        for fmt in (DECIMAL32, DECIMAL64, DECIMAL128):
            zeros = "0" * (fmt.bits // 4 - 2)
            self.assertEqual(bid_hex(fmt, Datum(0, "inf", 0, 0)), "#78" + zeros)
            self.assertEqual(bid_hex(fmt, Datum(0, "qnan", 0, 0)), "#7C" + zeros)
            self.assertEqual(dpd.hex_word(dpd.encode_infinity(False, fmt), fmt), "#78" + zeros)
            self.assertEqual(dpd.hex_word(dpd.encode_nan(False, False, 0, fmt), fmt), "#7C" + zeros)


class DpdTest(unittest.TestCase):
    def test_fixed_witnesses(self) -> None:
        for fmt, text in [(DECIMAL32, "#A23003D0"), (DECIMAL64, "#A2300000000003D0"), (DECIMAL128, "#A20780000000000000000000000003D0")]:
            self.assertEqual(dpd.hex_word(dpd.encode_finite(True, 750, -2, fmt), fmt), text)
            self.assertEqual(dpd.decode_finite(int(text[1:], 16), fmt), (True, 750, -2))


class ConversionTest(unittest.TestCase):
    def test_format_conversion_detects_tininess_before_rounding(self) -> None:
        value = bid_read(DECIMAL128, "#2CFFED09BEAD87C0378D8E63FFFFFFFF")
        exact = Decimal(value.coefficient).scaleb(value.exponent, Context(prec=60, Emax=10**6, Emin=-(10**6)))
        context = Context(prec=16, rounding=ROUND_HALF_EVEN, Emax=384, Emin=-383, traps=[], clamp=1)
        rounded = context.plus(exact)
        self.assertTrue(context.flags[Inexact])
        self.assertTrue(context.flags[Underflow])
        sign, digits, exponent = rounded.as_tuple()
        coefficient = int("".join(map(str, digits)))
        self.assertEqual(bid_hex(DECIMAL64, Datum(sign, "finite", coefficient, exponent)), "#00038D7EA4C68000")


if __name__ == "__main__":
    unittest.main()
