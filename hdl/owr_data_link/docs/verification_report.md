# owr_data_link: Verification Report

## 1. Test results

Run on 2026-10-14 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*owr_data_link*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `owr_data_link_tb` | 20 | 20 |

QuestaSim (Questa Pro Microchip Edition 2024.3) on 2026-10-14, complete regression without code coverage
(`python run.py --questa -p 1`): all 19 tests pass. TC-DL-43, added afterwards, passes in QuestaSim without and with
code coverage with the same cycle counts as in GHDL.

## 2. Summary

All 20 test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports
no errors and no warnings.

Measured values:

| Item | Value |
| --- | --- |
| ErrorReset, ErrorWait, Started and Connecting timers | 6.4 us and 12.8 us within the ranges of ECSS 5.5.7.1c, d |
| FCTs sent in Connecting with a receive FIFO of 64 | 7 |
| User data throughput at 100 Mb/s, packets of 1000 bytes | 79.96 Mb/s (99.9 % of the 80 Mb/s of 10-bit data characters) |
| Rate of the packet ports, `UserClk` 83.3 MHz | 39 beats in 39 cycles on the transmit port of A and on the receive port of B (one beat per cycle); the first burst of 15 beats on the transmit port takes 19 cycles, including the start-up of the VVC |

Findings:

| Finding | Resolution |
| --- | --- |
| The receive credit counter overflowed its range in a delta cycle of the simulation (stale FCT-sent event with the new credit) | Increment limited to 56; FCTs are only requested up to 48, so the limit never acts in a clock cycle |
| After a parity error the last data character before the error is not passed | Correct: its data bits are covered by the failing parity bit (ECSS 5.4.3.4b); the receiver passes only confirmed characters, the EEP follows the confirmed ones |
| QuestaSim with full optimisation (without code coverage) stopped at the first N-Char written to the receive FIFO: "Value 1 is out of range 0 to 0" in the implicit signal of the actual `to_integer(unsigned(RxLevel))` of the port `RxFifo_Level` (`natural range 0 to 64`) of the flow control manager. GHDL and QuestaSim with code coverage were not affected | The actual is the explicit signal `RxLevelNat` of the subtype of the port (rule in [conventions.md](../../../docs/conventions.md)); the hardware is unchanged. QuestaSim without code coverage passes all tests |

Observations:

- An FCT, N-Char or broadcast code received in Started cannot be produced from the line: Started is entered with
  gotNull either not yet asserted (then no character is decoded) or asserted (then the port moves to Connecting two
  cycles later, after its first Null). The exit is implemented as specified.
- The reserved place for the EEP of a recovery is always free with the FCT rule of DL-4 (section 3 of the
  architecture), so the wait for room of ECSS 5.5.8.4a.4 is implemented but not reachable with a FIFO of 64.
