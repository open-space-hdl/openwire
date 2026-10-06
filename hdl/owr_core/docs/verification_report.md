# owr_core: Verification Report

## 1. Test results

Run on 2026-10-06 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*owr_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `owr_core_tb` | 14 (13 in the default configuration, 1 in `no_services`) | 14 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan) and every seam
listed in the plan is crossed. VSG reports no errors and no warnings; `python lint/synth_check.py` synthesizes
`owr_core` with GHDL with and without the broadcast services, without errors and without inferred latches.

Measured values:

| Item | Value |
| --- | --- |
| A to B, 20 packets of 1000 bytes at 100 Mb/s, B to A sending at the same time | 2.060 ms: 77.7 Mb/s user data, 97.1 % of the data character rate |
| B to A, 20 packets of 600 bytes at 62.5 Mb/s, A to B sending at the same time | finished within 2.082 ms: 46.1 Mb/s or more, 92 % or more of the data character rate |

Findings during the core tests: none in the design. The tests found two errors of the test sequences (a missing
expectation of the packet after a truncated one, and a run bit period of B shorter than the sampling period of A in a
test that did not set the link speed); both were test errors. The second one shows a property of the system that the
[user guide](../../../docs/user_guide.md) states: the run bit period of a port must be longer than the clock period of
the far end's receiver.
