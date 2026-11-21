import unittest
from unittest import mock

import kernel_oracle as oracle


class GeneratorTests(unittest.TestCase):
    def test_lcg_matches_the_values_of_the_moonbit_generator(self) -> None:
        # state 0, one step: 1442695040888963407, output state >> 11
        random = oracle.Random(0)
        self.assertEqual(random.next(), 1442695040888963407 >> 11)
        self.assertEqual(
            random.next(),
            ((1442695040888963407 * 6364136223846793005 + 1442695040888963407) % 2**64) >> 11,
        )

    def test_shapes_have_the_documented_bit_length_and_form(self) -> None:
        random = oracle.Random(7)
        for bits in (1, 2, 8, 9, 64, 65, 300):
            for shape in (0, 1, 2, 3, 5, 6):
                self.assertEqual(oracle.value(random, bits, shape).bit_length(), bits)
            self.assertEqual(oracle.value(random, bits, 1), 2**bits - 1)
            self.assertEqual(oracle.value(random, bits, 2), 2 ** (bits - 1))
            self.assertEqual(oracle.value(random, bits, 4), max(1, 2 ** (bits - 1) - 1))
        for bits in (2, 9, 100):
            self.assertEqual(oracle.value(random, bits, 3), 2 ** (bits - 1) + 1)

    def test_digest_of_zero_is_the_single_byte_00(self) -> None:
        self.assertEqual(oracle.to_bytes(0), b"\x00")
        self.assertEqual(oracle.to_bytes(256), b"\x01\x00")
        step = ((oracle.FNV_BASIS ^ 0) * oracle.FNV_PRIME) % 2**64
        self.assertEqual(
            oracle.mix(oracle.FNV_BASIS, 0), ((step ^ 0xFF) * oracle.FNV_PRIME) % 2**64
        )

    def test_radix_conversion_agrees_with_the_builtins(self) -> None:
        random = oracle.Random(11)
        for bits in (1, 7, 64, 200, 1000):
            number = oracle.value(random, bits, 0)
            self.assertEqual(oracle.to_radix(number, 10), str(number))
            self.assertEqual(oracle.to_radix(number, 16), format(number, "x"))
            self.assertEqual(oracle.to_radix(number, 2), format(number, "b"))
            for radix in (3, 7, 36):
                self.assertEqual(int(oracle.to_radix(number, radix), radix), number)
        self.assertEqual(oracle.to_radix(0, 10), "0")


class RegressionTableTests(unittest.TestCase):
    def test_the_committed_digests_are_reproduced(self) -> None:
        self.assertEqual(oracle.check(), 0)

    def test_a_changed_committed_digest_is_reported(self) -> None:
        changed = dict(oracle.committed_regression())
        changed["mul"] ^= 1
        with mock.patch.object(oracle, "committed_regression", return_value=changed):
            self.assertFalse(oracle.check_regression())


def limbs_of(number: int) -> list[int]:
    count = (number.bit_length() + 63) // 64
    return [(number >> (64 * index)) & (2**64 - 1) for index in range(count)]


def from_limbs(limbs: list[int]) -> int:
    return sum(limb << (64 * index) for index, limb in enumerate(limbs))


class ResidueErrorClassTests(unittest.TestCase):
    """One injected error of each class of the table in the header of `kernel_oracle`.

    The product is a known one (two seeded 300-limb values); each test changes
    the integer the way a faulty routine would and asserts which of the four
    residues change, `True` for "differs from the residue of the true product".
    """

    def setUp(self) -> None:
        random = oracle.Random(3)
        self.product = oracle.value(random, 64 * 300, 0) * oracle.value(random, 64 * 300, 0)
        self.limbs = limbs_of(self.product)
        self.base = oracle.residues(self.product)

    def seen(self, damaged: int) -> list[bool]:
        return [a != b for a, b in zip(self.base, oracle.residues(damaged))]

    def test_moduli_orders_are_far_above_any_row(self) -> None:
        for prime in oracle.MODULI[2:]:
            order = 1
            power = 2**64 % prime
            current = power
            while current != 1:
                current = current * power % prime
                order += 1
                if order > 10**7:
                    break
            self.assertGreater(order, 10**7)
        self.assertEqual(2**64 % oracle.MODULI[0], 1)
        self.assertEqual(2**64 % oracle.MODULI[1], 8)

    def test_a_lost_or_doubled_carry_is_seen_by_every_residue(self) -> None:
        for delta in (-1, 1):
            limbs = self.limbs[:]
            limbs[100] = (limbs[100] + delta) % 2**64
            self.assertEqual(self.seen(from_limbs(limbs)), [True] * 4)

    def test_a_wrong_low_or_high_limb_is_seen_by_every_residue(self) -> None:
        for position in (0, len(self.limbs) - 1):
            limbs = self.limbs[:]
            limbs[position] ^= 1 << 17
            self.assertEqual(self.seen(from_limbs(limbs)), [True] * 4)

    def test_a_dropped_block_is_seen_by_every_residue(self) -> None:
        zeroed = self.limbs[:]
        zeroed[200:210] = [0] * 10
        removed = self.limbs[:]
        del removed[200:210]
        for damaged in (zeroed, removed):
            self.assertEqual(self.seen(from_limbs(damaged)), [True] * 4)

    def swap(self, first: int, second: int, size: int) -> int:
        limbs = self.limbs[:]
        limbs[first : first + size], limbs[second : second + size] = (
            limbs[second : second + size],
            limbs[first : first + size],
        )
        return from_limbs(limbs)

    def test_two_swapped_blocks_are_missed_by_m1_and_seen_by_the_primes(self) -> None:
        seen = self.seen(self.swap(100, 300, 10))
        self.assertEqual(seen, [False, True, True, True])
        # adjacent limbs swapped: the same blind spot of M1
        self.assertEqual(self.seen(self.swap(100, 101, 1)), [False, True, True, True])

    def test_swapped_blocks_a_multiple_of_61_limbs_apart_are_missed_by_m1_and_m2(self) -> None:
        seen = self.seen(self.swap(100, 161, 10))
        self.assertEqual(seen, [False, False, True, True])

    def test_a_block_shifted_by_one_limb_is_seen_by_every_residue(self) -> None:
        limbs = self.limbs[:]
        limbs[100:110] = limbs[101:111]
        self.assertEqual(self.seen(from_limbs(limbs)), [True] * 4)

    def test_the_whole_result_shifted_by_one_limb_is_missed_by_m1_only(self) -> None:
        self.assertEqual(self.seen(self.product << 64), [False, True, True, True])

    def test_the_residue_of_a_product_is_the_product_of_the_residues(self) -> None:
        random = oracle.Random(9)
        a = oracle.value(random, 64 * 20, 0)
        b = oracle.value(random, 64 * 13, 6)
        expected = oracle.residues(a * b)
        product = [x * y % m for x, y, m in zip(oracle.residues(a), oracle.residues(b), oracle.MODULI)]
        self.assertEqual(product, expected)


class RowSemanticsTests(unittest.TestCase):
    """The definitions behind the rows of the short product, limb and window tables."""

    def test_round_product_nearest_even_down_and_up(self) -> None:
        # 0b101101 rounded to 3 bits: kept 0b101, discarded 0b101 (above half)
        nearest, down, up = oracle.round_product(0b101101, 3)
        self.assertEqual(nearest, (0b11, 3 + 1))  # 0b110 stripped: 0b11, exponent 3 + 1
        self.assertEqual(down, (0b101, 3))
        self.assertEqual(up, (0b11, 4))
        # an exact tie, kept odd: rounds up; kept even: rounds down
        self.assertEqual(oracle.round_product(0b101100, 3)[0], (0b11, 4))
        self.assertEqual(oracle.round_product(0b100100, 3)[0], (0b1, 5))
        # an exact product has all three roundings equal
        self.assertEqual(len({tuple(x) for x in oracle.round_product(0b101000, 3)}), 1)

    def test_window_view_follows_the_documented_limb_formula(self) -> None:
        random = oracle.Random(5)
        for length in (1, 2, 5):
            for ws in (-3, -1, 0, 1, 4):
                for bs in (0, 1, 33, 63):
                    x = oracle.value(random, 64 * length, 0)
                    limbs = oracle.limbs_of_test(x, length) if hasattr(oracle, "limbs_of_test") else [
                        (x >> (64 * i)) & (2**64 - 1) for i in range(length)
                    ]
                    count = 7

                    def get(index: int) -> int:
                        return limbs[index] if 0 <= index < length else 0

                    expected = 0
                    for j in range(count):
                        word = (get(j - ws) << bs) & (2**64 - 1)
                        if bs:
                            word |= get(j - ws - 1) >> (64 - bs)
                        expected |= word << (64 * j)
                    self.assertEqual(oracle.window_view(x, length, ws, bs, count), expected)

    def test_the_submul_limb_is_the_carry_and_borrow_folded(self) -> None:
        # r - a b = r_new - c 2^(64 n) with 0 <= c < 2^64, for the extreme operands
        n = 3
        r = 0
        a = 2 ** (64 * n) - 1
        b = 2**64 - 1
        total = r - a * b
        new = total % 2 ** (64 * n)
        c = (new - total) // 2 ** (64 * n)
        self.assertEqual(r - a * b, new - c * 2 ** (64 * n))
        self.assertTrue(0 <= c < 2**64)

    def test_every_table_is_registered_and_named(self) -> None:
        self.assertEqual([table.name for table in oracle.TABLES], ["product", "short", "limbs", "window"])
        for table in oracle.TABLES:
            names = table.names()
            self.assertEqual(len(names), len(set(names)), table.name)


if __name__ == "__main__":
    unittest.main()
