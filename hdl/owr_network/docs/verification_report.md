# owr_network: Verification Report

## 1. Test results

Run on 2026-10-14 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*owr_network*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `owr_network_tb` | 15 (12 in the default configuration; TC-NI-11 in `no_services`, `time_codes_only`, `interrupts_only`) | 15 |

QuestaSim (Questa Pro Microchip Edition 2024.3) on 2026-10-16 with Open Logic 4.7.0-ft.6, complete regression without
code coverage (`python run.py --questa -p 1`) and with it: all 15 tests of `owr_network_tb` pass in both runs.

## 2. Summary

All 15 test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports
no errors and no warnings. The minimum interval of 5 ticks of 100 ns was measured as 500 ns to 600 ns plus the
request latency.

Findings: none in the design. During reset the outputs of the interrupt service are undefined in simulation (the
registers are reset at the first clock edge); the slot model of the testbench ignores them while the reset is active.
