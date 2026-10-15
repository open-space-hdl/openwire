# owr_core: Verification Report

## 1. Test results

Run on 2026-10-14 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*owr_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `owr_core_tb` | 21 (15 in the default configuration; TC-CORE-14 in `no_services`, `time_codes_only`, `interrupts_only`; TC-CORE-15 in `link_start`, `auto_start`, `link_disabled`) | 21 |
| `lint/synth_check.py` (TC-CORE-16) | 19 configurations that synthesise, 7 configurations outside the ranges | 26 |

QuestaSim (Questa Pro Microchip Edition 2024.3) on 2026-10-16 with Open Logic 4.7.0-ft.6, complete regression without
code coverage (`python run.py --questa -p 1`) and with it: all 21 tests of `owr_core_tb` pass in both runs.

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan) and every seam
listed in the plan is crossed. VSG reports no errors and no warnings; `python lint/synth_check.py` synthesizes
`owr_core` with GHDL at the bounds of every generic range, without errors and without inferred latches, and stops the
elaboration of every configuration outside the ranges with its message. The reset of each clock domain comes from the
triplicated reset synchroniser of `olo_base_reset_gen`.

Generics of `owr_core` (simulated: in a test of the regression; synthesised: by `lint/synth_check.py`):

| Generic | Declared range | Enforced by | Simulated values | Synthesised values |
| --- | --- | --- | --- | --- |
| `LinkClkFreq_g` | 18 to 22, 27 to 33, 36 to 44, 45 to 2554 MHz | `owr_encoding` (integer divider of 10 Mb/s), `owr_core` (13.2 MHz, initial divider 255) | 100 MHz (core A and the module testbenches), 125 MHz (core B) | 18, 22, 27, 33, 36, 44, 45, 100, 2554 MHz; 11, 25 and 2555 MHz stop |
| `TxFifoDepth_g` | Powers of 2, 2 to 32768 | Open Logic (power of 2, at least 2), `owr_core` (32768) | 2 (TC-DL-44), 64 | 2, 64, 32768; 1 and 65536 stop |
| `RxFifoDepth_g` | Powers of 2, 16 to 32768 | Open Logic (power of 2), `owr_core` (16 and 32768) | 16 (TC-DL-44), 64; 128 in the MIB testbench (register FIFO_DEPTHS) | 16, 64, 32768; 8 and 65536 stop |
| `TimeCodes_g`, `Interrupts_g` | boolean | type | All four combinations (core A, core B in TC-CORE-14, instances of TC-NI-11) | All four combinations |
| `IntTimerWidth_g` | 1 to 30 | type | 16 | 1, 16, 30 |
| `LinkDisabled_g`, `LinkStart_g`, `AutoStart_g` | boolean | type | false; each true at core B (TC-CORE-15); `LinkStart_g` true in the MIB testbench | false; all true |
| `RunDiv_g` | 1 to 255 | type | 1; 4 in the MIB testbench; run dividers 1, 2, 7 and 255 through LINK_SPEED (TC-EN-03) | 1, 255 |
| `SyncStages_g` | 2 to 4 | type | 2, 3, 4 (receive tests of `owr_encoding`) | 2, 4 |

The other generics of the modules are fixed inside the core or derived from its generics: `ReqDepth_g` 8 and
`IndDepth_g` 16 of `owr_network_broadcast`, `ReqDepth_g` 16 and `ReadTimeoutClks_g` 1000 of `owr_mib_bridge`,
`NumPulses_g` of `owr_cc_pulse` (2 and 4), and the cycle counts of the timers and the initial divider from
`LinkClkFreq_g`. They are covered by the values above.

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

Findings of the review of the generic ranges (2026-10-14), present in all earlier versions:

| Finding | Resolution |
| --- | --- |
| `RxFifoDepth_g` = 8 elaborated, but the receive FIFO has no room for the eight N-Chars of an FCT beside the reserved place of an EEP, so the port never sends an FCT and receives no data | Elaboration stops below 16 (CORE-CF-01); 16 is simulated (TC-DL-44) |
| FIFO depths of 65536 elaborated; the 16-bit fields FIFO_DEPTHS and FIFO_LEVELS read the depth and a full FIFO as 0 | Elaboration stops above 32768 (CORE-CF-01) |
| `LinkClkFreq_g` of 9 to 11 MHz elaborated, but the receiver cannot sample the initial rate of the far end (up to 11 Mb/s) | Elaboration stops below 13.2 MHz (CORE-CF-02) |
| `LinkClkFreq_g` of 2555 MHz or more elaborated; LINK_SPEED.INIT_DIV read 0 (initial divider 256 in 8 bits); no realistic configuration is affected | Elaboration stops at 2555 MHz and above (CORE-CF-02) |
| Mixed broadcast services (time-codes without interrupts and the reverse), 3 and 4 synchroniser stages and the reset values true of LinkDisabled, LinkStart and AutoStart had not been simulated, the bounds of IntTimerWidth_g, RunDiv_g and the FIFO depths not synthesised | Simulated and synthesised as listed above; no defect found |

GHDL simulator flags (record of 2026-10-14): VUnit 5.0.0.dev7 appends the generics of a test to the list of the option
`ghdl.sim_flags` in place, and a configuration added after that option was set shares the list with the configuration
it was copied from, so a GHDL simulation could inherit generics of earlier tests. `run.py` adds all configurations of
the testbenches (`owr_core_tb`, `owr_mib_tb`, `owr_cc_pulse_tb`) before it sets `ghdl.sim_flags`, and VUnit stores a
copy of the option in every configuration that exists at that moment, so every configuration had its own list. A probe
confirms it: with the copy removed, the generics check of `run.py` found only the own generics in the commands of the
three configurations of `owr_cc_pulse_tb`. Since then `run.py` copies the list for every GHDL
simulation and stops when a command does not carry exactly the generics of its configuration. QuestaSim passes the
generics per simulation and was not affected.
