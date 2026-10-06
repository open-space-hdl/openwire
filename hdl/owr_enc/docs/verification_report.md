# owr_enc: Verification Report

## 1. Test results

Run on 2026-10-06 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py "*owr_enc*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `owr_enc_tb` | 12 | 12 |

## 2. Summary

All 12 test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports
no errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| The transmitter took the presented character as its first character after Transmit Enable; ECSS 5.4.5 requires a Null | EN-1 sends a Null as the first character and takes the presented character only if it is a Null (EN-TX-06) |
| The reset input set data and strobe to '0' in the same cycle, a simultaneous transition when both were '1' (ECSS 5.4.4c) | Strobe is reset in the first and data in the second cycle of the reset (EN-TX-07) |
| Transmit Enable asserted again before the end of the controlled reset left data or strobe at '1' and the transmitter inactive until Transmit Enable was de-asserted again (found by the condition coverage) | The controlled reset continues while the transmitter is inactive; the restart follows at a bit boundary (EN-TX-07). In the core the link state machine keeps Transmit Enable low for at least 19.2 us, so the core was not affected |
| A first Null followed by a data character is not detected by a receiver (its last parity bit is '1') | Correct behaviour of ECSS 5.4.6 (Figure 5-18); the tests send a control character after the first Null, as the Started state does |

Observations:

- The receiver decodes a far-end bit period of 12 ns with a 100 MHz clock (1.2 clock periods); the model has no
  jitter, so the margin for skew and jitter on a real line is the difference to one clock period.
- After a simultaneous transition the receiver reported a parity or ESC error within 4 us in all 20 cases.
