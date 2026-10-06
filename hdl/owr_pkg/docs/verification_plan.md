# owr_pkg: Verification Plan

## 1. Overview

The functions of the package are checked against the values and the example of the standard (Figure 5-15), the pulse
crossing with two asynchronous clocks, and the far-end model in a self test: two model instances connected to each
other.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `owr_pkg_tb` | `owr_pkg_th` | `owr_cc_pulse` (100 MHz to 71.4 MHz), two `owr_tb_ds_bfm` connected to each other |
| `owr_cc_pulse_tb` | none | `owr_cc_pulse` with two pulse bits; a monitor counts the output pulses per bit and checks that each lasts one cycle. Three VUnit configurations: input clock faster (4 ns / 10 ns), output clock faster (10 ns / 4 ns), nearly equal (10 ns / 12 ns) |

Simulator: GHDL.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_functions` (TC-PKG-01) | Timer conversions, initial divider for 100, 125 and 200 MHz, parity of the example of ECSS Figure 5-15 (0x5C followed by a Null), model encoding of the same sequence | PKG-01, PKG-02, PKG-04 |
| `test_cc_pulse` (TC-PKG-02) | Ten pulse patterns on two pulses: every pulse arrives once, output pulses last one cycle | PKG-03 |
| `test_single_pulses` (TC-PKG-04) | 200 random pulses on bit 0, bit 1 or both, random spacing between one and two minimum spacings: one single-cycle output pulse per input pulse, within the latency | PKG-03 |
| `test_min_spacing` (TC-PKG-05) | 100 pulses on both bits at exactly the minimum spacing: no pulse lost | PKG-03 |
| `test_pending` (TC-PKG-06) | Two pulses in consecutive cycles, a pulse during a transfer, five consecutive pulses: two, two and two output pulses (pending pulse sent, further pulses merged) | PKG-03 |
| `test_reset` (TC-PKG-07) | Reset of both sides while idle, of the input side and of the output side during a transfer, with a pending pulse, and a pulse while the input side is in reset: no output pulse from a reset, at most one for a pulse in flight, none for a dropped pulse; pulses after the resets are transferred | PKG-03 |
| `test_ds_model` (TC-PKG-03) | First transition on the strobe line, 700 characters of all kinds decoded in order, no simultaneous transition, parity error, ESC error and simultaneous transition counted, controlled reset and restart | PKG-04 |
