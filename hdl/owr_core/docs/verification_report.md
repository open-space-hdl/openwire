# owr_core: Verification Report

## 1. Test results

Run on 2026-10-12 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*owr_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `owr_core_tb` | 14 (13 in the default configuration, 1 in `no_services`) | 14 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan) and every seam
listed in the plan is crossed. VSG reports no errors and no warnings; `python lint/synth_check.py` synthesizes
`owr_core` with GHDL with and without the broadcast services, without errors and without inferred latches. The
reset of each clock domain comes from the triplicated reset synchroniser of `olo_base_reset_gen`.

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

GHDL simulator flags (record of 2026-10-14): VUnit 5.0.0.dev7 appends the generics of a test to the list of the option
`ghdl.sim_flags` in place, and a configuration added after that option was set shares the list with the configuration
it was copied from, so a GHDL simulation could inherit generics of earlier tests. `run.py` adds all configurations of
the testbenches (`owr_core_tb`, `owr_mib_tb`, `owr_cc_pulse_tb`) before it sets `ghdl.sim_flags`, and VUnit stores a
copy of the option in every configuration that exists at that moment, so every configuration had its own list. A probe
confirms it: with the copy removed, the generics check of `run.py` found only the own generics in the commands of the
three configurations of `owr_cc_pulse_tb`. Since then `run.py` copies the list for every GHDL
simulation and stops when a command does not carry exactly the generics of its configuration. QuestaSim passes the
generics per simulation and was not affected.
