# owr_mib: Verification Report

## 1. Test results

Run on 2026-10-06 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*owr_mib*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `owr_mib_tb` | 11 (8 tests, TC-MG-09 in three configurations) | 11 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings; `python tools/regmap.py --check` confirms that the VHDL package, the register map and the C
header match the description.

Findings:

| Finding | Fix |
| --- | --- |
| The write data and byte enables of the AXI4-Lite slave are undefined before the first write; a first read carried them into the request FIFO and the ECC decoder propagated the undefined bits into the double error flag in simulation | Read requests carry zeros in the data fields |
| A read of ECC_COUNT in the cycle after a clear returned the value before the clear (read latency of the EDAC monitor) | The register file selects the read data one cycle after `Rb_Rd` |

Observation: the UVVM AXI4-Lite VVC issues a read in parallel with a preceding write (AXI4-Lite has no ordering
between the read and write channels); software that needs the value of a write waits for the write response, as
TC-MG-09 does.
