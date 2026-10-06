# owr_pkg: Verification Plan

## 1. Overview

The functions of the package are checked against the values and the example of the standard (Figure 5-15), the pulse
crossing with two asynchronous clocks, and the far-end model in a self test: two model instances connected to each
other.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `owr_pkg_tb` | `owr_pkg_th` | `owr_cc_pulse` (100 MHz to 71.4 MHz), two `owr_tb_ds_bfm` connected to each other |

Simulator: GHDL.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_functions` (TC-PKG-01) | Timer conversions, initial divider for 100, 125 and 200 MHz, parity of the example of ECSS Figure 5-15 (0x5C followed by a Null), model encoding of the same sequence | PKG-01, PKG-02, PKG-04 |
| `test_cc_pulse` (TC-PKG-02) | Ten pulse patterns on two pulses: every pulse arrives once, output pulses last one cycle | PKG-03 |
| `test_ds_model` (TC-PKG-03) | First transition on the strobe line, 700 characters of all kinds decoded in order, no simultaneous transition, parity error, ESC error and simultaneous transition counted, controlled reset and restart | PKG-04 |
