# owr_pkg: Verification Report

## 1. Test results

Run on 2026-10-06 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20:
`python run.py "*owr_pkg*" "*owr_cc_pulse*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `owr_pkg_tb` | 3 | 3 |
| `owr_cc_pulse_tb` | 12 (4 tests in 3 configurations) | 12 |

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings in the far-end model during its self test, all fixed:

| Finding | Fix |
| --- | --- |
| The receiver of the model consumed the first real edge as initialisation when the lines were already '0' at time zero | Previous values start as 'U'; the lines are taken as initialised when they are '0' or '1' |
| Waiting on a function of a shared variable never resumes | `tbWaitTxEmpty` polls the transmit queue |
