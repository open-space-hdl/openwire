# owr_enc: Specification

## 1. Overview

`owr_enc` is the Encoding layer of OpenWire (ECSS-E-ST-50-12C Rev.1 clause 5.4). It encodes the characters and
control codes of the Data Link layer into symbols with odd parity, serialises them and drives the data and strobe
signals; in the other direction it samples the data and strobe signals, recovers the bit stream, detects the first
Null and decodes the characters, and reports parity errors, ESC errors and disconnects.

| Block | Entity | Function |
| --- | --- | --- |
| EN-1 | `owr_enc_tx` | Transmitter: encoding, parity, serialisation, Data-Strobe encoding, first Null, controlled reset, bit rate |
| EN-2 | `owr_enc_rx` | Receiver: sampling Data-Strobe decoder, de-serialisation, Null detection, decoding, parity, ESC and disconnect errors |
| EN-3 | `owr_enc` | Port loopback and the connection of EN-1 and EN-2 |

All blocks run in `LinkClk`. The data and strobe inputs are asynchronous to `LinkClk`.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| EN-IF-01 | The Encoding layer shall take one character or control code (Null, FCT, data character, EOP, EEP, broadcast code) from the Data Link layer at the end of every transmitted character while Transmit Enable is asserted, and acknowledge it with a one-cycle pulse. | 5.2.4a.1, b, 5.5.2b, 6.3.1.2 |
| EN-IF-02 | The Encoding layer shall pass every received character and control code to the Data Link layer as a one-cycle event with its kind and data, and report parity errors, ESC errors and disconnects as one-cycle events and gotNull as a level. | 5.2.4a.2, 5.4.2f, 5.5.2c, 6.3.2.2, 6.3.2.4 to 6.3.2.6 |
| EN-IF-03 | The Encoding layer shall be controlled by the Transmit Enable and Receive Enable flags: Transmit Enable enables the transmitter and resets it when de-asserted, Receive Enable enables the receiver and resets it when de-asserted. | 5.4.2e, 6.3.1.3, 6.3.2.3 |
| EN-IF-04 | The Encoding layer shall drive single-ended data and strobe outputs and receive single-ended data and strobe inputs for the line drivers and receivers of the target. | 5.2.4d, 5.2.8f, g, 6.4.1, 6.4.2 |

### 2.2 Transmitter (EN-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| EN-TX-01 | A data character shall be encoded as parity bit, data-control flag '0' and the eight data bits least significant bit first. | 5.4.3.1 |
| EN-TX-02 | A control character shall be encoded as parity bit, data-control flag '1' and the two-bit control type (FCT 0b00, EOP 0b10, EEP 0b01, ESC 0b11), least significant bit first. | 5.4.3.2 |
| EN-TX-03 | A Null shall be encoded as ESC followed by FCT, a broadcast code as ESC followed by a data character carrying the broadcast code. | 5.4.3.3 |
| EN-TX-04 | Every parity bit shall make the number of ones odd over the data or control bits of the previous character, the parity bit and the data-control flag. | 5.4.3.4 |
| EN-TX-05 | Characters shall be serialised in the order they are taken and Data-Strobe encoded: data follows the bit, strobe changes when the bit equals the previous bit. | 5.4.2a, 5.4.4a |
| EN-TX-06 | Data and strobe shall be zero after reset. The first character after Transmit Enable is asserted shall be a Null whose first bit is a zero parity bit, so that the first transition is on the strobe line. | 5.4.4b, 5.4.5 |
| EN-TX-07 | When Transmit Enable is de-asserted, the transmitter shall stop sending characters and reset strobe and data one at a time: the signal that is '1' first at the next bit boundary (strobe before data), the other one bit period of the initial rate later, so that data and strobe never change together. | 5.4.4c, d, e |
| EN-TX-08 | Outside the Run state the bit period shall be the initial divider, computed from the clock frequency for 10 Mb/s +/- 1 Mb/s; in the Run state it shall be the run divider of the link speed parameter (1 to 255 clock cycles). A new divider shall take effect at a bit boundary. | 5.4.10.1, 5.4.10.2, 5.4.10.4a, 5.4.11 |
| EN-TX-09 | The maximum transmit data signalling rate shall be the clock frequency (run divider 1). | 5.4.10.3 |

### 2.3 Receiver (EN-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| EN-RX-01 | Data and strobe shall be synchronised to the clock and sampled every clock cycle; a bit shall be recovered on every change of data XOR strobe with the value of data. A simultaneous transition of data and strobe shall not lock up the receiver. | 5.4.4f, 5.4.2b |
| EN-RX-02 | While Receive Enable is asserted and before gotNull, the receiver shall search the bit stream for the sequence 011101000 (parity, flag and type of an ESC, of an FCT, and the parity bit of the next character) and assert gotNull when it is found. gotNull shall only be cleared when Receive Enable is de-asserted. | 5.4.6 |
| EN-RX-03 | After gotNull the receiver shall decode every character, combine ESC with the next character into a Null or a broadcast code, and pass characters and control codes to the Data Link layer in the order received. | 5.4.2b, d, 5.4.3 |
| EN-RX-04 | While gotNull is asserted a parity error shall be detected when the parity over the previous data or control bits, the parity bit and the data-control flag is not odd. A character shall only be passed when the parity bit of the next character has been checked without error. | 5.4.2c, 5.4.7 |
| EN-RX-05 | While gotNull is asserted an ESC followed by ESC, EOP or EEP shall produce an ESC error. | 5.4.9 |
| EN-RX-06 | Disconnect detection shall be enabled by the first edge on data or strobe after Receive Enable is asserted; a disconnect shall be reported when no edge occurred for more than 727 ns and at most 1 us. | 5.4.8 |
| EN-RX-07 | After an error the receiver shall pass no further character and report no further error until Receive Enable is de-asserted. | 5.4.2c |
| EN-RX-08 | The receiver shall decode a far-end data signalling rate up to a bit period of 1.2 clock periods (MinsepIN of one clock period plus margin) and down to the minimum rate allowed by the disconnect time. | 5.3.7.2j, 5.4.10.2, 5.4.10.3, 5.4.10.4a |

### 2.4 Port loopback (EN-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| EN-LB-01 | When the loopback is enabled, the receiver shall receive the data and strobe signals of the own transmitter instead of the inputs. | 5.6.10f |

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Parity not odd | EN-2 at the data-control flag of a character | Parity error event; the character before is not passed; receiver halted until Receive Enable is de-asserted |
| ESC followed by ESC, EOP or EEP | EN-2 when the second character has been checked | ESC error event; receiver halted |
| No edge for the disconnect time | EN-2 timer, after the first edge | Disconnect event; receiver halted |
| Simultaneous transition | Not detectable as such: two bits are lost | Parity error of a later character |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `ClkFreq_g` | 100.0e6 | 20 MHz to 400 MHz | Frequency of `LinkClk` in Hz; must allow 10 Mb/s +/- 10 % with an integer divider |
| `SyncStages_g` | 2 | 2 to 4 | Synchroniser stages of the data and strobe inputs |

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 5.4.4e | The delay between the reset of strobe and data is one bit period of the initial rate (100 ns), which lies between the fastest bit period and 500 ns |
| 5.4.2c, 5.4.3.4b | The parity bit of character n+1 covers the data bits of character n; character n is therefore passed only after the parity of character n+1 is checked (two bits later) |
| 5.4.9 | An ESC error is reported when the character after the ESC has been checked by the parity of the following character, in the order of the stream |
