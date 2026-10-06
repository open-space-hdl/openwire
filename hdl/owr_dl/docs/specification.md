# owr_dl: Specification

## 1. Overview

`owr_dl` is the Data Link layer of OpenWire (ECSS-E-ST-50-12C Rev.1 clause 5.5). It holds the transmit and receive
FIFOs of the port, controls the flow of N-Chars with flow control tokens, selects the next character for the
Encoding layer by the sending priority, runs the link state machine and recovers from link errors.

| Block | Entity | Function |
| --- | --- | --- |
| DL-1 | `owr_dl` (`olo_ft_fifo_async`) | Transmit FIFO, `UserClk` to `LinkClk` |
| DL-2 | `owr_dl` (`olo_ft_fifo_async`) | Receive FIFO, `LinkClk` to `UserClk`, double error containment on the user side |
| DL-3 | `owr_dl_lsm` | Link state machine |
| DL-4 | `owr_dl_fc` | Flow control manager: credit counters, FCT requests, credit errors |
| DL-5 | `owr_dl_tx` | Transmit scheduler: sending priority, broadcast code slot, discarding of a packet remainder |
| DL-6 | `owr_dl_rx` | Receive handler: N-Chars to the receive FIFO, broadcast codes to the Network layer, EEP after an error |
| DL-7 | `owr_dl_rec` | Link error recovery state machine |

All blocks except the user sides of the FIFOs run in `LinkClk`.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-IF-01 | The Data Link layer shall accept N-Chars (9 bit: end of packet marker flag and 8 bit data, EOP 0x00, EEP 0x01) from the user with a valid / ready handshake into the transmit FIFO and pass received N-Chars from the receive FIFO with a valid / ready handshake, both in `UserClk`. | 5.5.2a, d, e, f, 5.2.8b, c, 6.2.1 |
| DL-IF-02 | The Data Link layer shall accept broadcast codes from the Network layer with a valid / ready handshake and pass received broadcast codes as one-cycle events. | 5.5.2a, d, g, 6.2.2 |
| DL-IF-03 | The Data Link layer shall present one character or control code to the Encoding layer at all times and take the acknowledge of the Encoding layer, and take the received characters and control codes, gotNull and the error events of the Encoding layer. | 5.5.2b, c, i |
| DL-IF-04 | The Data Link layer shall control the Encoding layer with Transmit Enable, Receive Enable and the run rate select. | 5.5.2h, 5.4.2e |
| DL-IF-05 | The Data Link layer shall be controlled by the management parameters PortReset, LinkDisabled, LinkStart and AutoStart. | 5.5.3a |
| DL-IF-06 | The Data Link layer shall provide the link state, the error events (disconnect, parity, ESC, credit), the transmit and receive credit counters, the recovery state with the cause of the last error and the fill levels of both FIFOs. | 5.5.3b, 5.5.8.4a.5 |

### 2.2 FIFOs (DL-1, DL-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-FI-01 | The transmit FIFO shall store N-Chars from the user until they are sent; the receive FIFO shall store received N-Chars until the user reads them. Depths are generics. | 5.2.8b, c |
| DL-FI-02 | Port reset shall clear both FIFOs. | 5.5.7.1e.1 |
| DL-FI-03 | An N-Char read with a double error from the receive FIFO shall be passed to the user as an EEP, followed by the discard of the received N-Chars up to and including the next end of packet marker. | none (P5) |

### 2.3 Link state machine (DL-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-LS-01 | The link state machine shall implement the states ErrorReset, ErrorWait, Ready, Started, Connecting and Run with the actions and the exit conditions of the standard, evaluated in the order given there. | 5.5.7.1a, b, 5.5.7.2 to 5.5.7.7 |
| DL-LS-02 | In ErrorReset Transmit Enable and Receive Enable shall be de-asserted and gotFCT cleared; ErrorReset shall be left to ErrorWait 6.4 us (5.82 us to 7.22 us) after entry when LinkDisabled is de-asserted. | 5.5.7.2, 5.5.7.1c |
| DL-LS-03 | ErrorWait shall last 12.8 us (11.64 us to 14.33 us) with Receive Enable asserted and move to Ready; LinkDisabled, a disconnect, a parity error, an ESC error or a received FCT, N-Char or broadcast code shall move it to ErrorReset. | 5.5.7.3, 5.5.7.1d |
| DL-LS-04 | Ready shall move to Started on LinkStart or on AutoStart with gotNull, and to ErrorReset on the error conditions of ErrorWait. | 5.5.7.4 |
| DL-LS-05 | Started shall assert Transmit Enable with Nulls only, move to Connecting when at least one Null has been sent and gotNull is asserted, and to ErrorReset on the error conditions or 12.8 us after entry. | 5.5.7.5 |
| DL-LS-06 | Connecting shall send FCTs and Nulls, move to Run when at least one FCT has been sent and an FCT has been received (gotFCT), and to ErrorReset on LinkDisabled, disconnect, parity error, ESC error, a received N-Char or broadcast code, or 12.8 us after entry. | 5.5.7.6 |
| DL-LS-07 | Run shall send broadcast codes, FCTs, N-Chars and Nulls, select the run data signalling rate, pass received N-Chars and broadcast codes, and move to ErrorReset on LinkDisabled, disconnect, parity error, ESC error or credit error. | 5.5.7.7, 5.4.10.4 |
| DL-LS-08 | Port reset shall move the link state machine to ErrorReset from any state. | 5.5.7.1e.2 |

### 2.4 Flow control (DL-4)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-FC-01 | The transmit credit counter shall be incremented by eight for every FCT received in Connecting or Run and decremented by one for every N-Char sent; it shall be zero in ErrorReset and have a maximum of 56. | 5.5.4a, b, e, g, h |
| DL-FC-02 | N-Chars shall only be sent while the transmit credit counter is above zero. | 5.5.4d, f, 5.5.6d.3 |
| DL-FC-03 | The receive credit counter shall be incremented by eight for every FCT sent and decremented by one for every N-Char received in Run; it shall be zero in ErrorReset and have a maximum of 56. | 5.5.4l, m, n, o |
| DL-FC-04 | An FCT shall be requested in Connecting and Run when the receive FIFO has room for eight more N-Chars beyond the receive credit (and a pending EEP) and the receive credit is at most 48, so that one FCT per eight N-Chars of room and at most seven FCTs are outstanding. | 5.5.4c, i, k, p |
| DL-FC-05 | A credit error shall be detected when an FCT would increase the transmit credit above 56 or an N-Char is received with a receive credit of zero; the N-Char is not stored. | 5.5.4j, 5.5.5 |

### 2.5 Transmit scheduler (DL-5)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-TX-01 | The scheduler shall present, by state: in Started a Null; in Connecting an FCT when requested, otherwise a Null; in Run a broadcast code when one is waiting, otherwise an FCT when requested, otherwise an N-Char when one is available and the transmit credit is above zero, otherwise a Null. | 5.5.6a to e, 5.5.7.5a.2, 5.5.7.6a.2, 5.5.7.7a.1 |
| DL-TX-02 | The scheduler shall signal Sent Null and Sent FCT to the link state machine and N-Char sent and FCT sent to the flow control manager. | 5.5.7.5b.6, 5.5.7.6b.5 |
| DL-TX-03 | A broadcast code from the Network layer shall be accepted into a slot of one code in Run and sent at the next character boundary; outside Run it shall be accepted and discarded (reported), and a waiting code shall be discarded in ErrorReset. | 5.5.9, 5.5.6b, 5.5.7.2b, 6.2.2.2 |
| DL-TX-04 | When the link error recovery starts and the last N-Char sent in Run was a data character, the scheduler shall read and discard the transmit FIFO up to and including the next EOP or EEP; no N-Char is sent before this is done. | 5.5.8.4a.1 |
| DL-TX-05 | An N-Char read with a double error from the transmit FIFO shall be sent as an EEP, followed by the discard of the transmit FIFO up to and including the next end of packet marker. | none (P5) |

### 2.6 Receive handler (DL-6)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-RX-01 | In Run, received N-Chars shall be written to the receive FIFO in the order received and received broadcast codes passed to the Network layer; outside Run no N-Char shall be stored and no broadcast code registered. | 5.5.2c, d, 5.5.7.3a.3, 5.5.7.4a.2, 5.5.7.5a.3, 5.5.7.6a.3, 5.5.7.7a.3, a.4 |
| DL-RX-02 | When the link error recovery starts and the last character written to the receive FIFO was a data character, an EEP shall be written to the receive FIFO, waiting for room when the FIFO is full. | 5.5.8.4a.2 to a.4 |

### 2.7 Link error recovery (DL-7)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DL-RC-01 | The link error recovery state machine shall move from Normal to Recovery when, in Run, LinkDisabled is asserted or a disconnect, parity error, ESC error or credit error occurs; it shall record the cause and return to Normal when the recovery actions of DL-5 and DL-6 are complete. | 5.5.8.1, 5.5.8.3, 5.5.8.4 |
| DL-RC-02 | Port reset shall move the link error recovery state machine to Normal and cancel the recovery actions. | 5.5.8.2 |

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Disconnect, parity error, ESC error | EN-2 | ErrorReset; recovery when in Run |
| FCT, N-Char or broadcast code received before Run | DL-3 (events of EN-2) | ErrorReset (N-Char and broadcast code also in Connecting) |
| Credit error | DL-4 | ErrorReset when in Run; the N-Char is not stored |
| No FCT within 12.8 us in Connecting | DL-3 | ErrorReset |
| Double error in the transmit FIFO | DL-5 | EEP sent, rest of the packet discarded |
| Double error in the receive FIFO | DL-2 user side | EEP passed, rest of the packet discarded |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `ClkFreq_g` | 100.0e6 | 20 MHz to 400 MHz | Frequency of `LinkClk` in Hz (timers of 6.4 us and 12.8 us) |
| `TxFifoDepth_g` | 64 | 16 to any power of 2 | Depth of the transmit FIFO in N-Chars |
| `RxFifoDepth_g` | 64 | 16 to any power of 2 | Depth of the receive FIFO in N-Chars; 64 or more allows seven outstanding FCTs |

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 5.5.7.5b.6, 5.5.7.6b.5 | "Sent Null" and "Sent FCT" are signalled when the transmitter takes the character; the next character can only follow the complete one, so the far end sees the same order |
| 5.5.5, 5.5.7.6b | A credit error in Connecting (more than seven FCTs received before Run) is reported but does not change the state: Connecting lists no credit error exit. The counter saturates at 56 |
| 5.5.8.4a.1 | The discard of the packet remainder starts at the transition to Recovery and is independent of the link state; it may end after the link has returned to Run, and no N-Char is sent until it ends |
| 5.5.4p | The room in the receive FIFO is its depth minus its fill level, minus one N-Char that may be on its way into the FIFO, minus a pending EEP |
