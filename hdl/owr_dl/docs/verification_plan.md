# owr_dl: Verification Plan

## 1. Overview

The Data Link layer is verified together with the Encoding layer at the line: port A against the Data-Strobe far-end
model, which sends any character sequence (also sequences a correct port never sends) and logs every character of
port A, and port A against a second port B for traffic. Tests observe the ports, the status outputs and the line only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `owr_dl_tb` | `owr_dl_th`, `owr_dl_tb_port` | Ports A and B (each `owr_enc` + `owr_dl`, FIFOs of 64), LinkClk 100 MHz, UserClk 83.3 MHz, far-end model at 10 Mb/s on the line of A (`LinkMode` = '0') or B (`LinkMode` = '1'), `Cut` freezes both directions, AXI4-Stream VVCs on the N-Char ports (TLAST = marker beat), counters of the status events |

Simulator: GHDL. The run divider of the ports is 1 (100 Mb/s) unless stated.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_lsm_startup` (TC-DL-01) | ErrorReset 5.82 to 7.22 us and ErrorWait 11.64 to 14.33 us after reset; Started on LinkStart and its timeout without far end; with Nulls: only Nulls in Started, Connecting, seven FCTs, no N-Char, Run on one FCT; credits 8 and 56 | DL-LS-01 to DL-LS-07, DL-FC-01, DL-FC-03, DL-FC-04, DL-IF-03, DL-IF-04, DL-IF-05, DL-IF-06, DL-TX-01, DL-TX-02 |
| `test_lsm_autostart` (TC-DL-02) | AutoStart waits in Ready without a Null, starts on gotNull | DL-LS-04, DL-IF-05 |
| `test_lsm_disabled` (TC-DL-03) | LinkDisabled keeps ErrorReset with the receiver disabled; LinkDisabled in Connecting, Run (with recovery and cause), ErrorWait, Ready and Started | DL-LS-01 to DL-LS-07, DL-RC-01 |
| `test_lsm_timeouts` (TC-DL-04) | Started and Connecting time out after 11.64 to 14.33 us | DL-LS-05, DL-LS-06 |
| `test_lsm_errors` (TC-DL-05) | FCT, N-Char and broadcast code received in ErrorWait and Ready; parity error, ESC error and disconnect in Ready; N-Char, broadcast code (not stored, not passed) and disconnect in Connecting; parity error, ESC error and disconnect in Run with recovery and cause | DL-LS-01, DL-LS-03, DL-LS-04, DL-LS-06, DL-LS-07, DL-RX-01, DL-RC-01 |
| `test_port_reset` (TC-DL-06) | Port reset in Run clears both FIFOs, credits and the state; the link restarts; port reset during a recovery that waits for the end of a packet returns to Normal and stops the discard | DL-LS-08, DL-FI-01, DL-FI-02, DL-RC-02 |
| `test_fc_rx_credit` (TC-DL-10) | Seven FCTs for a FIFO of 64; no FCT while the FIFO has no room for 8 more; one FCT after reading 8 N-Chars; the full credit of 56 received without reading; seven FCTs after reading | DL-FC-03, DL-FC-04 |
| `test_fc_tx_credit` (TC-DL-11) | Exactly 8 N-Chars per FCT received; transmit credit counter | DL-FC-01, DL-FC-02, DL-TX-01 |
| `test_fc_credit_errors` (TC-DL-12) | FCT raising the transmit credit above 56; N-Char with a receive credit of zero: credit error, ErrorReset, cause, the N-Char not stored, EEP after the data | DL-FC-05, DL-RC-01, DL-RX-02 |
| `test_tx_priority` (TC-DL-20) | Broadcast code, FCT request and N-Chars pending at one character boundary: sent in the order broadcast code, FCT, N-Chars | DL-TX-01, DL-TX-03 |
| `test_bc_service` (TC-DL-21) | Broadcast code outside Run discarded and reported; four codes in Run sent; received time-code and interrupt code passed in Run; a code waiting in the slot is discarded in ErrorReset | DL-TX-03, DL-RX-01, DL-IF-02 |
| `test_rec_tx_discard` (TC-DL-30) | Disconnect after 8 of 100 data characters: the rest of the packet is discarded from the transmit FIFO, the next packet is sent complete after the restart; cause disconnect | DL-TX-04, DL-RC-01 |
| `test_rec_rx_eep` (TC-DL-31) | Parity error after data characters: the data confirmed by a parity check followed by an EEP; ESC error after a complete packet: no EEP; causes | DL-RX-02, DL-RC-01 |
| `test_rec_restart` (TC-DL-32) | Disconnect in the middle of a packet whose source pauses; the link returns to Run while the remainder is discarded; a parity error in Run restarts the recovery with the new cause; the recovery ends when the remainder up to the EOP is discarded, nothing of it is sent, the next packet is sent complete | DL-RC-01, DL-TX-04 |
| `test_link_traffic` (TC-DL-40) | Ports A and B: 60 packets of 0 to 300 bytes in each direction with EOP and EEP; 20 packets of 1000 bytes at 100 Mb/s at 95 % or more of 8 Mb/s user data per 10 Mb/s | DL-IF-01, DL-FI-01, DL-TX-01, DL-RX-01 |
| `test_link_backpressure` (TC-DL-41) | Random gaps on the transmit side and random back-pressure on the receive side, 50 packets | DL-IF-01, DL-FC-04 |
| `test_link_restart` (TC-DL-42) | Line cut for 3 us in the middle of a packet: both ports restart, the packet arrives as a prefix with EEP, the following packets are complete | DL-TX-04, DL-RX-02, DL-RC-01 |
| `test_ecc_tx` (TC-DL-50) | Single error injected into the transmit FIFO corrected and counted; double error: EEP sent, rest of the packet discarded, next packet complete | DL-TX-05 |
| `test_ecc_rx` (TC-DL-51) | Single error injected into the receive FIFO corrected and counted; double error: EEP passed, rest of the packet discarded, next packet complete | DL-FI-03 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| DL-IF-01 | TC-DL-40, TC-DL-41 |
| DL-IF-02 | TC-DL-21 |
| DL-IF-03, DL-IF-04, DL-IF-06 | TC-DL-01 |
| DL-IF-05 | TC-DL-01, TC-DL-02 |
| DL-FI-01 | TC-DL-06, TC-DL-40 |
| DL-FI-02 | TC-DL-06 |
| DL-FI-03 | TC-DL-51 |
| DL-LS-01 to DL-LS-07 | TC-DL-01, TC-DL-03, TC-DL-04, TC-DL-05 |
| DL-LS-08 | TC-DL-06 |
| DL-FC-01 | TC-DL-01, TC-DL-11 |
| DL-FC-02 | TC-DL-11 |
| DL-FC-03, DL-FC-04 | TC-DL-01, TC-DL-10 |
| DL-FC-05 | TC-DL-12 |
| DL-TX-01 | TC-DL-01, TC-DL-11, TC-DL-20 |
| DL-TX-02 | TC-DL-01 |
| DL-TX-03 | TC-DL-20, TC-DL-21 |
| DL-TX-04 | TC-DL-30, TC-DL-32, TC-DL-42 |
| DL-TX-05 | TC-DL-50 |
| DL-RX-01 | TC-DL-05, TC-DL-21, TC-DL-40 |
| DL-RX-02 | TC-DL-12, TC-DL-31, TC-DL-42 |
| DL-RC-01 | TC-DL-03, TC-DL-05, TC-DL-12, TC-DL-30, TC-DL-31, TC-DL-32 |
| DL-RC-02 | TC-DL-06 |

## 5. Negative tests

| Checker | Test |
| --- | --- |
| Received character outside Run | TC-DL-05 |
| Started and Connecting timeouts | TC-DL-04 |
| Transmit credit overflow, N-Char without credit | TC-DL-12 |
| Broadcast code outside Run | TC-DL-21 |
| Double error in the transmit and receive FIFO | TC-DL-50, TC-DL-51 |
