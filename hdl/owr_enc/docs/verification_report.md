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
| A first Null followed by a data character is not detected by a receiver (its last parity bit is '1') | Correct behaviour of ECSS 5.4.6 (Figure 5-18); the tests send a control character after the first Null, as the Started state does |

Observations:

- The receiver decodes a far-end bit period of 12 ns with a 100 MHz clock (1.2 clock periods); the model has no
  jitter, so the margin for skew and jitter on a real line is the difference to one clock period.
- After a simultaneous transition the receiver reported a parity or ESC error within 4 us in all 20 cases.
