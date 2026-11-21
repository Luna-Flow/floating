import unittest

import decimal_kernel_oracle as oracle


class GeneratorTests(unittest.TestCase):
    def test_xorshift_step_written_out_by_hand(self) -> None:
        # seed 1: x ^= x << 13 gives 8193, x ^= x >> 7 gives 8257, x ^= x << 17 gives 1082269761
        self.assertEqual(oracle.Random(1).next(), 1082269761)

    def test_xorshift_wraps_to_64_bits(self) -> None:
        random = oracle.Random(0x9E3779B97F4A7C15)
        for _ in range(100):
            self.assertLess(random.next(), 2**64)

    def test_digest_is_fnv1a_of_the_text_then_one_ff_step(self) -> None:
        digest = oracle.Digest()
        digest.add("a")
        state = ((0xCBF29CE484222325 ^ ord("a")) * 0x100000001B3) % 2**64
        state = ((state ^ 0xFF) * 0x100000001B3) % 2**64
        self.assertEqual(digest.state, state)

    def test_digest_separates_values(self) -> None:
        one = oracle.Digest()
        one.add(12)
        one.add(3)
        other = oracle.Digest()
        other.add(1)
        other.add(23)
        self.assertNotEqual(one.state, other.state)

    def test_rounding_table_on_the_cases_of_gda(self) -> None:
        # 25 / 10 = 2.5 (a tie), 26 / 10 = 2.6, 24 / 10 = 2.4, 35 / 10 = 3.5
        rows = {
            ("HalfEven", 25): 2, ("HalfEven", 35): 4, ("HalfUp", 25): 3, ("HalfDown", 25): 2,
            ("HalfDown", 26): 3, ("HalfUp", 24): 2, ("Down", 29): 2, ("Up", 21): 3,
            ("ZeroFiveUp", 21): 2, ("ZeroFiveUp", 29): 2, ("ZeroFiveUp", 11): 1,
            ("ZeroFiveUp", 1): 1, ("ZeroFiveUp", 51): 6, ("ZeroFiveUp", 59): 6,
        }
        for (mode, value), expected in rows.items():
            self.assertEqual(oracle.round_pow10(value, 1, False, mode), (expected, True), (mode, value))
        # the direction depends on the sign for Ceiling and Floor
        self.assertEqual(oracle.round_pow10(21, 1, False, "Ceiling"), (3, True))
        self.assertEqual(oracle.round_pow10(21, 1, True, "Ceiling"), (2, True))
        self.assertEqual(oracle.round_pow10(21, 1, False, "Floor"), (2, True))
        self.assertEqual(oracle.round_pow10(21, 1, True, "Floor"), (3, True))
        # an exact quotient is not inexact and not rounded
        for mode in oracle.MODES:
            self.assertEqual(oracle.round_pow10(30, 1, False, mode), (3, False))

    def test_finite_expansion_by_the_definition(self) -> None:
        self.assertTrue(oracle.finite_expansion(1, 8))
        self.assertTrue(oracle.finite_expansion(1, 50))
        self.assertFalse(oracle.finite_expansion(1, 3))
        self.assertTrue(oracle.finite_expansion(3, 3))
        self.assertTrue(oracle.finite_expansion(21, 42 * 5))
        self.assertFalse(oracle.finite_expansion(1, 7 * 10**20))

    def test_scaled_quotient_rule(self) -> None:
        digest = oracle.Digest()
        oracle.scaled_add(digest, 1, 0, 3)  # 1/3: quotient 0, last digit 0, incremented to 1
        reference = oracle.Digest()
        for value in (1, 0, 3, 1):
            reference.add(value)
        self.assertEqual(digest.state, reference.state)
        digest = oracle.Digest()
        oracle.scaled_add(digest, 1, 0, 4)  # 1/4 has a finite expansion: zero
        reference = oracle.Digest()
        for value in (1, 0, 4, 0):
            reference.add(value)
        self.assertEqual(digest.state, reference.state)

    def test_value_generators_give_nonzero_top_limbs(self) -> None:
        random = oracle.Random(5)
        for length in (1, 2, 7):
            for _ in range(50):
                self.assertGreater(oracle.round_value(random, length, 3), 10 ** (9 * (length - 1)) - 1 if length == 1 else 0)
                self.assertGreaterEqual(oracle.random_limbs(random, length), 10 ** (9 * (length - 1)))


if __name__ == "__main__":
    unittest.main()
