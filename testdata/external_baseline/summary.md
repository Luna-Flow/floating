### Binary: floating `bin_float` against MPFR

Ratio floating / MPFR (median time, 95% bootstrap interval; above 1 means floating is slower)

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 8.74 [8.66, 8.84] | 6.41 [6.32, 6.59] | 6.96 [6.90, 7.04] | 6.34 [6.23, 6.51] | 5.15 [5.11, 5.18] |
| mul | 7.58 [7.51, 7.65] | 3.98 [3.93, 4.07] | 3.79\* [3.72, 3.82] | 3.93 [3.90, 3.96] | 3.92 [3.92, 3.93] |
| div | 7.94 [7.92, 8.06] | 5.88 [5.83, 5.93] | 3.19 [3.17, 3.24] | 3.70 [3.66, 3.73] | 4.76 [4.75, 4.77] |
| sqrt | 10.12 [9.99, 10.22] | 1.90 [1.90, 1.92] | 4.60 [4.56, 4.68] | 4.12 [4.06, 4.18] | 4.28 [4.24, 4.37] |
| exp | 3.09 [3.06, 3.13] | 2.52 [2.51, 2.54] | 2.50 [2.48, 2.52] | 5.23 [5.17, 5.29] | 2.99 [2.96, 3.02] |
| ln | 6.92 [6.89, 7.09] | 4.60 [4.55, 4.64] | 6.20 [6.16, 6.23] | 10.87 [10.80, 10.94] | 9.54 [9.45, 9.58] |
| sin | 8.84 [8.76, 8.93] | 7.70 [7.61, 7.76] | 7.26 [7.23, 7.31] | 10.13 [10.08, 10.22] | 5.24 [5.18, 5.26] |

Median ns per operation, MPFR

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 4.59 ns | 6 ns | 12.4 ns | 21.7 ns | 85.6 ns |
| mul | 5 ns | 10.1 ns | 32 ns | 231 ns | 2.13 us |
| div | 5.38 ns | 26.3 ns | 106 ns | 498 ns | 4 us |
| sqrt | 5.64 ns | 62.3 ns | 162 ns | 509 ns | 2.83 us |
| exp | 557 ns | 846 ns | 2.35 us | 16.8 us | 208 us |
| ln | 388 ns | 1.09 us | 3.41 us | 14.9 us | 116 us |
| sin | 496 ns | 792 ns | 2.22 us | 14.1 us | 197 us |

Median ns per operation, floating

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 40.1 ns | 38.5 ns | 86.2 ns | 138 ns | 441 ns |
| mul | 37.9 ns | 40 ns | 121 ns | 910 ns | 8.34 us |
| div | 42.8 ns | 154 ns | 340 ns | 1.84 us | 19 us |
| sqrt | 57.1 ns | 119 ns | 745 ns | 2.1 us | 12.1 us |
| exp | 1.72 us | 2.13 us | 5.89 us | 87.7 us | 619 us |
| ln | 2.69 us | 4.99 us | 21.2 us | 162 us | 1.11 ms |
| sin | 4.38 us | 6.1 us | 16.1 us | 143 us | 1.03 ms |

### Decimal GDA: floating `decimal_gda` against libmpdec

Ratio floating / libmpdec (median time, 95% bootstrap interval; above 1 means floating is slower)

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 3.63 [3.60, 3.67] | 11.39 [11.23, 11.55] | 8.71 [8.61, 8.83] | 6.01 [5.89, 6.13] |
| mul | 4.25 [4.20, 4.30] | 5.41 [5.27, 5.63] | 3.03 [3.00, 3.06] | 1.74 [1.72, 1.77] |
| div | 2.95 [2.90, 2.98] | 6.15 [6.09, 6.25] | 4.33 [4.28, 4.37] | 3.09 [3.07, 3.11] |
| sqrt | 5.31 [5.28, 5.35] | 4.27 [4.24, 4.31] | 2.77 [2.75, 2.78] | 2.12 [2.10, 2.13] |
| exp | 2.92 [2.88, 2.95] | 1.53 [1.52, 1.55] | 1.39 [1.38, 1.41] | 0.11 [0.11, 0.11] |
| ln | 1.28 [1.27, 1.29] | 0.96 [0.96, 0.98] | 1.17 [1.16, 1.18] | 0.28 [0.27, 0.28] |

Median ns per operation, libmpdec

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 20 ns | 21.9 ns | 35.1 ns | 171 ns |
| mul | 19.4 ns | 48.7 ns | 136 ns | 9.05 us |
| div | 31.6 ns | 122 ns | 328 ns | 14.5 us |
| sqrt | 307 ns | 1.07 us | 4.03 us | 213 us |
| exp | 2.97 us | 7.97 us | 17.5 us | 4.69 ms |
| ln | 9.94 us | 18 us | 43.2 us | 5.24 ms |

Median ns per operation, floating

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 72.5 ns | 249 ns | 306 ns | 1.03 us |
| mul | 82.6 ns | 264 ns | 413 ns | 15.7 us |
| div | 93.3 ns | 750 ns | 1.42 us | 44.8 us |
| sqrt | 1.63 us | 4.55 us | 11.2 us | 451 us |
| exp | 8.67 us | 12.2 us | 24.3 us | 523 us |
| ln | 12.7 us | 17.4 us | 50.4 us | 1.45 ms |

### Harness overhead of the floating side

| case | ns per operation (loop and result store only) |
| --- | ---: |
| `binary/null/53` | 9.21 ns [9.15 ns, 9.26 ns] |
| `decimal_gda/null/16` | 9.21 ns [9.14 ns, 9.32 ns] |

Cells marked with an asterisk exceeded a dispersion threshold (CI half-width over 5% of the median, or round medians spread by over 10%): `binary/mul/512`.
