# owr_enc: Verification Plan

## 1. Overview

The Encoding layer is verified against the Data-Strobe far-end model, which encodes and decodes characters in
continuous time with its own implementation of the standard. The transmitter is checked through the characters and
edges the model decodes, the receiver through the characters and events it passes; the far-end model also injects
parity errors, illegal ESC sequences, simultaneous transitions, bit sequences around the first Null and pauses.
Tests observe ports only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `owr_enc_tb` | `owr_enc_th` | `owr_enc` at 100 MHz (initial divider 10), far-end model instance 0 on the line, character source of the transmitter from queue 1, log of the receiver in log 1 |

Simulator: GHDL. The character sequences are deterministic and mix all kinds (data, FCT, EOP, EEP, Null and broadcast
codes).

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_first_null` (TC-EN-01) | Data and strobe '0' after reset; first transition on the strobe line, first character a Null with a zero parity bit, initial bit period 100 ns; after a restart the first Null is sent before the presented character, which is then taken once | EN-TX-06, EN-TX-08, EN-IF-01, EN-IF-03, EN-IF-04 |
| `test_tx_characters` (TC-EN-02) | 2000 characters of all kinds are decoded by the far end in order and without parity error | EN-TX-01 to EN-TX-05, EN-IF-01 |
| `test_tx_rates` (TC-EN-03) | Run dividers 1, 2, 7 and 255: every edge one bit period after the previous one and the sequence decoded; initial rate outside Run; rate changes every 1.7 us only at bit boundaries | EN-TX-08, EN-TX-09 |
| `test_tx_reset` (TC-EN-04) | Transmit Enable de-asserted at 16 points: strobe reset at the next bit boundary, data 100 ns later, no simultaneous transition; restart with a first Null; Transmit Enable low for one cycle with data and strobe at "01", "10" and "11": reset completed, first Null one bit period after the last reset edge, no simultaneous transition; reset input asserted with data and strobe at '1': strobe first, data one cycle later | EN-TX-07, EN-TX-06, EN-IF-03 |
| `test_null_detection` (TC-EN-10) | Characters without a Null: no gotNull, no character passed; the Null sequence with each of its three parity bits wrong is not detected, the correct sequence is; gotNull cleared only by Receive Enable; a Null after a data character with an odd number of ones is not the first Null | EN-RX-02, EN-IF-02 |
| `test_rx_characters` (TC-EN-11) | 3000 characters of all kinds at 50 Mb/s passed in order; the last character is passed only after the parity bit of the next one | EN-RX-01, EN-RX-03, EN-RX-04, EN-IF-02 |
| `test_rx_parity` (TC-EN-12) | Parity error in an FCT, a data character, an EOP and the ESC of a broadcast code: error event, the character before is not passed, no further event; reception after restart | EN-RX-04, EN-RX-07 |
| `test_rx_esc_error` (TC-EN-13) | ESC followed by ESC, EOP and EEP: ESC error, the character before the ESC is passed | EN-RX-05, EN-RX-07 |
| `test_rx_disconnect` (TC-EN-14) | No disconnect before the first edge; five disconnects with the time from the last edge between 727 ns and 1 us; no disconnect at 2 Mb/s | EN-RX-06, EN-RX-08 |
| `test_rx_simultaneous` (TC-EN-15) | 20 simultaneous transitions at different bit positions: a later parity or ESC error, no lock-up, reception after restart | EN-RX-01, EN-RX-07 |
| `test_rx_rates` (TC-EN-16) | 200 characters at bit periods of 12 ns (1.2 clock periods), 17 ns, 100 ns, 333 ns and 500 ns (2 Mb/s) | EN-RX-08 |
| `test_loopback` (TC-EN-17) | Port loopback: the receiver gets gotNull from the own transmitter and receives 500 characters at the run divider 4 | EN-LB-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| EN-IF-01 | TC-EN-01, TC-EN-02 |
| EN-IF-02 | TC-EN-10, TC-EN-11 |
| EN-IF-03 | TC-EN-01, TC-EN-04 |
| EN-IF-04 | TC-EN-01 |
| EN-TX-01 to EN-TX-05 | TC-EN-02 |
| EN-TX-06 | TC-EN-01, TC-EN-04 |
| EN-TX-07 | TC-EN-04 |
| EN-TX-08 | TC-EN-01, TC-EN-03 |
| EN-TX-09 | TC-EN-03 |
| EN-RX-01 | TC-EN-11, TC-EN-15 |
| EN-RX-02 | TC-EN-10 |
| EN-RX-03 | TC-EN-11 |
| EN-RX-04 | TC-EN-11, TC-EN-12 |
| EN-RX-05 | TC-EN-13 |
| EN-RX-06 | TC-EN-14 |
| EN-RX-07 | TC-EN-12, TC-EN-13, TC-EN-15 |
| EN-RX-08 | TC-EN-14, TC-EN-16 |
| EN-LB-01 | TC-EN-17 |

## 5. Negative tests

| Checker | Test |
| --- | --- |
| Parity check | TC-EN-12, TC-EN-15 |
| ESC error | TC-EN-13 |
| Disconnect timer | TC-EN-14 |
| Null detection (three parity bits) | TC-EN-10 |
