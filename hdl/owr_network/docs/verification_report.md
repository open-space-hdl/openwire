# owr_network: Verification Report

## 1. Test results

Run on 2026-10-11 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*owr_network*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `owr_network_tb` | 13 | 13 |

## 2. Summary

All 13 test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports
no errors and no warnings. The minimum interval of 5 ticks of 100 ns was measured as 500 ns to 600 ns plus the
request latency.

Findings: none in the design. During reset the outputs of the interrupt service are undefined in simulation (the
registers are reset at the first clock edge); the slot model of the testbench ignores them while the reset is active.
