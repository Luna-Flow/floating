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
            self.assertEqual(oracle.check(), 1)


if __name__ == "__main__":
    unittest.main()
