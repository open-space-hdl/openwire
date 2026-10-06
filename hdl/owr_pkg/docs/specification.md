# owr_pkg: Specification

## 1. Overview

`owr_pkg` contains the definitions shared by all OpenWire modules: the package `owr_pkg` (character kinds, N-Char
format, link states, broadcast code fields, timer conversions, parity), the generated register package `owr_regs_pkg`
and the pulse crossing `owr_cc_pulse`. The shared verification components in `tb/` (Data-Strobe far-end model) are
verified with this module.

## 2. Requirements

| ID | Requirement | ECSS |
| --- | --- | --- |
| PKG-01 | The package shall define the character kinds (Null, FCT, data, EOP, EEP, broadcast code), the control types (FCT 0b00, EOP 0b10, EEP 0b01, ESC 0b11), the N-Char format (flag and 8 data bits, EOP 0x00, EEP 0x01), the link states and the causes of an error recovery. | 5.4.3.2, 5.5.7 |
| PKG-02 | The package shall convert durations into clock cycles, compute the initial divider for 10 Mb/s and compute the odd parity bit over the previous data or control bits and the data-control flag. | 5.4.3.4, 5.4.10.1 |
| PKG-03 | `owr_cc_pulse` shall transfer pulses between two clock domains with single-cycle output pulses: free of latches, state registers triplicated with majority voters, level crossings with `olo_ft_cc_bits`, resets of both sides coupled with `olo_ft_cc_reset`. Every input pulse shall give exactly one output pulse within 3 input plus 4 output clock cycles when the pulses of one bit are at least 5 input plus 5 output clock cycles apart; one further pulse during a transfer shall be stored and sent afterwards. | none (implementation) |
| PKG-04 | The Data-Strobe far-end model shall encode characters with odd parity and Data-Strobe encoding, decode the received signals in continuous time after the first Null, count parity errors, ESC errors and simultaneous transitions, and inject parity errors and simultaneous transitions. | 5.4.3, 5.4.4, 5.4.6 |

`owr_cc_pulse` merges the pulses of one bit that arrive during a transfer into one pending pulse (closer than 5
input plus 5 output clock cycles, after the first pending one); pulses during the reset of either side, including
the synchronised release, are dropped.

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `owr_cc_pulse.NumPulses_g` | 1 | 1 to any | Number of independent pulses |
