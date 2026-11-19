### Binary: floating `bin_float` against MPFR

Ratio floating / MPFR (median time, 95% bootstrap interval; above 1 means floating is slower)

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 22.13 [22.02, 22.24] | 21.22 [20.97, 21.49] | 18.06 [17.90, 18.45] | 16.36 [16.24, 16.49] | 15.59 [15.56, 15.61] |
| mul | 20.02 [19.85, 20.15] | 13.27 [13.22, 13.33] | 10.66 [10.60, 10.75] | 10.93 [10.89, 10.96] | 12.76 [12.73, 12.80] |
| div | 33.35 [33.17, 33.47] | 8.94 [8.87, 9.00] | 6.20 [6.15, 6.29] | 8.59 [8.56, 8.63] | 13.80 [13.76, 13.84] |
| sqrt | 39.53 [39.30, 39.80] | 7.84 [7.78, 7.86] | 49.87 [49.49, 50.31] | 27.81 [27.70, 27.96] | 27.87 [27.72, 28.03] |
| exp | 65.06 [64.66, 65.49] | 77.14 [76.66, 77.79] | 102 [102, 103] | 187 [186, 187] | 411 [410, 412] |
| ln | 141 [141, 142] | 107 [107, 108] | 155 [155, 156] | 561 [559, 563] | 2472 [2460, 2475] |
| sin | 435 [433, 436] | 433 [431, 435] | 577 [575, 582] | 1214 [1210, 1217] | 2554 [2548, 2561] |

Median ns per operation, MPFR

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 4.57 ns | 6 ns | 12.4 ns | 21.8 ns | 85.9 ns |
| mul | 5.01 ns | 10.1 ns | 32 ns | 232 ns | 2.14 us |
| div | 5.4 ns | 26.4 ns | 108 ns | 514 ns | 4.07 us |
| sqrt | 5.65 ns | 62.9 ns | 166 ns | 522 ns | 2.97 us |
| exp | 559 ns | 851 ns | 2.38 us | 17 us | 213 us |
| ln | 388 ns | 1.1 us | 3.45 us | 15.1 us | 116 us |
| sin | 503 ns | 803 ns | 2.23 us | 14.2 us | 198 us |

Median ns per operation, floating

| op | 53 bits | 128 bits | 512 bits | 2048 bits | 8192 bits |
| --- | ---: | ---: | ---: | ---: | ---: |
| add | 101 ns | 127 ns | 225 ns | 357 ns | 1.34 us |
| mul | 100 ns | 134 ns | 341 ns | 2.54 us | 27.3 us |
| div | 180 ns | 236 ns | 668 ns | 4.42 us | 56.2 us |
| sqrt | 223 ns | 493 ns | 8.26 us | 14.5 us | 82.7 us |
| exp | 36.4 us | 65.7 us | 244 us | 3.18 ms | 87.4 ms |
| ln | 54.7 us | 118 us | 536 us | 8.47 ms | 286 ms |
| sin | 218 us | 348 us | 1.29 ms | 17.3 ms | 507 ms |

### Decimal GDA: floating `decimal_gda` against libmpdec

Ratio floating / libmpdec (median time, 95% bootstrap interval; above 1 means floating is slower)

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 16.01 [15.87, 16.23] | 11.57 [11.44, 11.70] | 8.58 [8.33, 8.68] | 6.67 [6.62, 6.72] |
| mul | 16.04 [15.87, 16.14] | 6.37 [6.11, 6.47] | 3.13 [3.08, 3.18] | 1.77 [1.74, 1.81] |
| div | 22.11 [21.84, 22.27] | 8.02 [7.91, 8.14] | 4.73 [4.68, 4.83] | 3.14 [3.04, 3.20] |
| sqrt | 5.95 [5.81, 6.02] | 4.34 [4.32, 4.39] | 2.77 [2.73, 2.82] | 2.11 [2.03, 2.15] |
| exp | 86.94 [86.35, 87.29] | 36.54\* [36.29, 36.79] | 95.74 [95.46, 96.24] | 65.62 [64.19, 67.00] |
| ln | 22.42 [22.31, 22.54] | 22.36 [22.24, 22.65] | 24.46 [24.33, 24.70] | 15.02 [14.68, 15.24] |

Median ns per operation, libmpdec

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 19.2 ns | 23.5 ns | 43.2 ns | 160 ns |
| mul | 18.4 ns | 47.5 ns | 142 ns | 9.68 us |
| div | 30.1 ns | 119 ns | 343 ns | 15.3 us |
| sqrt | 289 ns | 1.09 us | 4.13 us | 211 us |
| exp | 2.85 us | 8.01 us | 17.6 us | 4.98 ms |
| ln | 9.87 us | 15.8 us | 40.7 us | 5.95 ms |

Median ns per operation, floating

| op | 16 digits | 34 digits | 100 digits | 1000 digits |
| --- | ---: | ---: | ---: | ---: |
| add | 307 ns | 273 ns | 371 ns | 1.07 us |
| mul | 296 ns | 303 ns | 446 ns | 17.2 us |
| div | 666 ns | 955 ns | 1.62 us | 47.9 us |
| sqrt | 1.72 us | 4.71 us | 11.4 us | 445 us |
| exp | 248 us | 293 us | 1.69 ms | 327 ms |
| ln | 221 us | 353 us | 996 us | 89.4 ms |

### Harness overhead of the floating side

| case | ns per operation (loop and result store only) |
| --- | ---: |
| `binary/null/53` | 9.28 ns [9.23 ns, 9.4 ns] |
| `decimal_gda/null/16` | 9.36 ns [9.28 ns, 9.48 ns] |

Cells marked with an asterisk exceeded a dispersion threshold (CI half-width over 5% of the median, or round medians spread by over 10%): `decimal_gda/exp/34`.
