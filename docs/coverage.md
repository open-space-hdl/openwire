# OpenWire: Code Coverage

## 1. Method

The code coverage of the OpenWire sources is measured with QuestaSim (Questa Pro Microchip Edition 2024.3) over the
complete regression of `run.py`, the same test set that GHDL runs in CI:

```shell
python run.py --questa --coverage -p 1
```

The sources of `hdl/<module>/src` are compiled with `+cover=sbcef`: statements, branches, conditions, expressions
(focused expression coverage) and state machines. Open Logic, UVVM and the testbenches are not instrumented; Open Logic
is verified by its own regression. `run.py` merges the coverage of all tests into `coverage/coverage.ucdb` and writes
the reports `coverage/coverage_report.txt` (details per instance) and `coverage/coverage_byfile.txt`; a design unit
is covered when any of its instances in any test covers it.

Closure rules:

- Statements, branches, state machine states and transitions: every item is covered by a test or listed with its
  justification in section 4.
- Conditions and expressions: reported, not a closure criterion. Focused expression coverage requires every input
  term to change the result while the other terms do not mask it; many combinations cannot occur by construction (for
  example an EDAC flag of a FIFO is only defined together with its valid signal) or need two independent events in
  the same clock cycle. Their misses were reviewed for untested behaviour (section 3).
- `-- coverage off` / `-- coverage on` are used for one kind of code only: the `when others` branch of a state machine
  whose enumerated state type lists every state. The branch is the recovery path of an illegal state (architecture
  D8) and cannot be reached in simulation.

## 2. Result

Run on 2026-10-06: 84 tests, all passed, 11 minutes with one simulator licence. Numbers are covered/total bins per
file; bold marks a metric with misses.

| File | Statements | Branches | FSM States | FSM Transitions | Conditions | Expressions |
| --- | --- | --- | --- | --- | --- | --- |
| `owr_core/src/owr_core.vhd` | 4/4 | 2/2 |  |  |  |  |
| `owr_dl/src/owr_dl.vhd` | 17/17 | 17/17 | 2/2 | 2/2 | **4/6** | **12/14** |
| `owr_dl/src/owr_dl_fc.vhd` | 27/27 | 25/25 |  |  | 11/11 | 6/6 |
| `owr_dl/src/owr_dl_lsm.vhd` | 48/48 | 50/50 | 6/6 | 10/10 | **28/31** | 12/12 |
| `owr_dl/src/owr_dl_rec.vhd` | 25/25 | 22/22 | 3/3 | **4/5** | 2/2 |  |
| `owr_dl/src/owr_dl_rx.vhd` | **38/39** | **21/22** |  |  | **8/10** | 6/6 |
| `owr_dl/src/owr_dl_tx.vhd` | 54/54 | 39/39 |  |  | **7/8** | 4/4 |
| `owr_enc/src/owr_enc.vhd` | 4/4 | 4/4 |  |  |  |  |
| `owr_enc/src/owr_enc_rx.vhd` | 95/95 | 44/44 | 3/3 | **4/5** | **4/5** | 4/4 |
| `owr_enc/src/owr_enc_tx.vhd` | 69/69 | 33/33 |  |  | 10/10 | 2/2 |
| `owr_mib/src/owr_mib.vhd` | 20/20 | 2/2 |  |  |  | **5/6** |
| `owr_mib/src/owr_mib_bridge.vhd` | 25/25 | 14/14 |  |  | 4/4 | **23/28** |
| `owr_mib/src/owr_mib_regs.vhd` | 181/181 | 83/83 |  |  | **6/8** | 2/2 |
| `owr_ni/src/owr_ni.vhd` | 23/23 |  |  |  |  | 2/2 |
| `owr_ni/src/owr_ni_bc.vhd` | 70/70 | 36/36 |  |  | 14/14 | **30/38** |
| `owr_ni/src/owr_ni_int.vhd` | 75/75 | 43/43 |  |  | 6/6 |  |
| `owr_ni/src/owr_ni_tc.vhd` | 26/26 | 13/13 |  |  |  |  |
| `owr_pkg/src/owr_cc_pulse.vhd` | 19/19 | 8/8 |  |  |  |  |
| `owr_pkg/src/owr_pkg.vhd` | **4/9** |  |  |  |  | **0/2** |
| Total | 824/830 (99.3 %) | 456/457 (99.8 %) | 14/14 (100.0 %) | 20/22 (90.9 %) | 104/115 (90.4 %) | 108/126 (85.7 %) |

## 3. Gaps found and closed

The first run (98.8 % of the statements, 98.7 % of the branches, 86.4 % of the state machine transitions) showed
behaviour that the requirements ask for but no test exercised, and the review of the condition misses found one
design defect. The tests below close these gaps.

| Gap | Test |
| --- | --- |
| Transmitter: Transmit Enable asserted again before the end of the controlled reset (condition miss in `owr_enc_tx`). The transmitter stayed inactive with data or strobe at '1' until Transmit Enable was de-asserted again. Design fix: the controlled reset continues while the transmitter is inactive, the restart follows at a bit boundary at least one bit period after the last reset edge (EN-TX-07). The core was not affected: the link state machine keeps Transmit Enable low for at least 19.2 us | TC-EN-04 (extended: restart with data and strobe at "01", "10" and "11") |
| Link error recovery: a new error in Run while the recovery still discards the remainder of a packet (transition Recovery to Starting) | TC-DL-32 (new) |
| Interrupt timers with the tick setting 0 (one tick per cycle); acknowledgement delay of every identifier | TC-NI-09 (extended) |
| MIB: ECC_INJECT written without SINGLE and DOUBLE | TC-MG-08 (extended) |
| Register bridge: request FIFO without room, new accesses held (MG-BR-01); reachable only with a management clock several times faster than `LinkClk` (expression miss in `owr_mib_bridge`) | TC-MG-09 (new configuration `mgmt_very_fast`, 500 MHz) |

The remaining condition and expression misses fall into three groups, none of them behaviour without a test:

- Coincidences of independent events in one clock cycle: a double error on the receive FIFO while the user is not
  ready, a double error on an end of packet marker during the discard of a packet, a disconnect in the cycle of a
  received bit, an EEP of a recovery while the write register of the receive handler is occupied.
- Terms that are masked by construction: the EDAC flags of a FIFO are defined only together with its valid and ready
  signals (`owr_dl.vhd`, `owr_ni_bc.vhd`, `owr_mib_bridge.vhd`); a grant of the request arbiter while the request FIFO
  is full; a read request or a double error in the register request FIFO while the request FIFO has no room.
- An FCT, N-Char or broadcast code received in Started (`owr_dl_lsm.vhd` line 166): Started is entered with gotNull
  either not yet asserted (then no character is decoded) or asserted (then the port moves to Connecting two cycles
  later, after its first Null). The exit to ErrorReset is implemented as ECSS 5.5.7.5 specifies; the same terms in
  Ready and Connecting are covered.

## 4. Remaining misses

One statement, one branch and two state machine transitions of the design remain uncovered, and five statements of a
package function are reported as not executed. None of them is behaviour that a requirement asks for:

| Location | Item not covered | Justification |
| --- | --- | --- |
| `owr_dl/src/owr_dl_rx.vhd:111`, statement 112 | Branch: N-Char lost because the write register to the receive FIFO is occupied (EVENTS.RX_OVERFLOW) | Defensive. The flow control (DL-4) gives credit only for free places of the receive FIFO, so the FIFO always accepts the word, and received N-Chars are at least four bits apart, while the write register empties in one cycle. |
| `owr_dl/src/owr_dl_rec.vhd:138` | Transition Starting to Normal | Reset input asserted in the one-cycle state Starting. The return to Normal is covered from Recovery, at the end of the recovery actions and by the port reset (TC-DL-06). |
| `owr_enc/src/owr_enc_rx.vhd:319` | Transition Flag to Parity | Reset input asserted while the receiver waits for the data-control flag of a character, a state of one bit period. The phase is used only after the first Null, whose detection sets it (line 230), so its reset value has no effect; the first Null after a reset is covered by TC-EN-10. |
| `owr_pkg/src/owr_pkg.vhd:162` to `166` | Statements: body of `xorReduce` | The calls on lines 88 and 103 of `owr_enc_tx.vhd` are covered; QuestaSim evaluates the call without executing the body as statements. The result, the parity of every transmitted character, is checked by TC-EN-02 and TC-EN-03. |

## 5. Reproduction

```shell
python run.py --questa --coverage -p 1
vcover report -byfile -details -zeros -code sbf coverage/coverage.ucdb
```

The second command lists the statements, branches and state machine items that are not covered, per file.
