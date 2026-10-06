# owr_ni: Specification

## 1. Overview

`owr_ni` is the Network layer of a SpaceWire node with one end-point (ECSS-E-ST-50-12C Rev.1 clause 5.6): the
time-code service with the time-code register, the distributed interrupt service in interrupt mode and in interrupt
with acknowledgement mode, and the broadcast code service that orders the codes for the Data Link layer and decodes
the received codes. The packet service (NI-1) is the N-Char stream of the Data Link layer FIFOs and is connected in
the core top level.

| Block | Entity | Function |
| --- | --- | --- |
| NI-1 | `owr_core` (wiring) | Packet ports of the end-point |
| NI-2 | `owr_ni_tc` | Time-code register, TIME-CODE.request and .indication, valid time-codes |
| NI-3 | `owr_ni_int` | Interrupt register, interrupt and acknowledgement codes, interrupt modes, minimum intervals |
| NI-4 | `owr_ni_bc` | Request and indication FIFOs to `UserClk`, priority of broadcast codes, decoding of received codes |

The Network layer functions run in `LinkClk`; the user ports of the broadcast services are in `UserClk`.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| NI-IF-01 | The Network layer shall accept TIME-CODE.request (6-bit value), DISTRIBUTED_INTERRUPT.request and DISTRIBUTED_INTERRUPT_ACK.request (5-bit interrupt identifier) on AXI4-Stream ports in `UserClk`, and from the MIB in `LinkClk`. | 6.1.2.2, 6.1.3.2, 6.1.3.4, 5.6.6f, j |
| NI-IF-02 | The Network layer shall pass TIME-CODE.indication, DISTRIBUTED_INTERRUPT.indication and DISTRIBUTED_INTERRUPT_ACK.indication on AXI4-Stream ports in `UserClk`; an indication that finds its FIFO full is discarded and reported. | 6.1.2.3, 6.1.3.3, 6.1.3.5, 5.6.6g, i |
| NI-IF-03 | The Network layer shall pass broadcast codes to the Data Link layer with a valid / ready handshake and take the received broadcast codes of the Data Link layer. | 5.2.2e, 6.2.2 |
| NI-IF-04 | The Network layer shall provide the time-code register, the interrupt register and events (valid and invalid time-code, interrupt and acknowledgement received, request discarded, received code ignored) for the MIB. | 5.6.7 |

### 2.2 Broadcast codes (NI-4)

| ID | Requirement | ECSS |
| --- | --- | --- |
| NI-BC-01 | Broadcast codes shall be passed to the Data Link layer in the order of priority time-code, interrupt acknowledgement code, interrupt code. | 5.6.3d |
| NI-BC-02 | A received broadcast code shall be decoded by its type: 0b00 time-code, 0b10 distributed interrupt code (bit 5: '0' interrupt, '1' acknowledgement); a code of type 0b01 or 0b11 shall be discarded and reported. | 5.6.3a, b, c, f |
| NI-BC-03 | A request or indication read with a double error from its FIFO shall be discarded and reported. | none (P5) |

### 2.3 Time-codes (NI-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| NI-TC-01 | Time-codes shall be optional (generic); without them received time-codes are ignored and requests are discarded. | 5.6.4.1, 5.2.2b |
| NI-TC-02 | A TIME-CODE.request shall load the time-code register with the value and send a time-code with that value; a request that arrives before the previous one was passed to the Data Link layer replaces it. | 5.6.4.4b, c, 6.1.2.2.4, 5.6.4.2 |
| NI-TC-03 | A received time-code whose value is the time-code register plus one modulo 64 shall be valid and indicated with its value; any other value is invalid and reported. In both cases the time-code register shall take the received value. | 5.6.4.3a, b, 5.6.4.5, 5.6.4.8, 5.6.4.9 |
| NI-TC-04 | Port reset shall set the time-code register to zero. | 5.6.4.3d |

### 2.4 Distributed interrupts (NI-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| NI-IN-01 | Distributed interrupts shall be optional (generic); without them received interrupt and acknowledgement codes are ignored and requests are discarded. | 5.6.5.1a, b |
| NI-IN-02 | The node shall operate in interrupt mode or in interrupt with acknowledgement mode, selected by a configuration parameter. | 5.6.5.1c, d |
| NI-IN-03 | A DISTRIBUTED_INTERRUPT.request shall send an interrupt code (type 0b10, bit 5 '0', identifier in bits 4:0). A request for an identifier whose previous interrupt code was sent less than the configured minimum interval ago, or is still waiting, shall be discarded and reported. | 5.6.5.2, 5.6.5.4a, b, c, d, 6.1.3.2.4 |
| NI-IN-04 | A received interrupt code shall set its bit in the interrupt register and be indicated with its identifier. | 5.6.5.4e, 6.1.3.3 |
| NI-IN-05 | A DISTRIBUTED_INTERRUPT_ACK.request shall clear the bit of the identifier in the interrupt register; in interrupt with acknowledgement mode it shall also send an acknowledgement code (type 0b10, bit 5 '1', identifier in bits 4:0), not earlier than the configured delay after the interrupt code arrived; in interrupt mode no code is sent. | 5.6.5.3, 5.6.5.6b, c, d, e, 6.1.3.4.4 |
| NI-IN-06 | In interrupt with acknowledgement mode a received acknowledgement code shall be indicated with its identifier; in interrupt mode it shall be discarded and reported. | 5.6.5.6g, h, 6.1.3.5 |
| NI-IN-07 | The minimum interval and the acknowledgement delay shall be counted in ticks of a configurable number of clock cycles. | 5.6.5.4c, d, 5.6.5.6e |
| NI-IN-08 | Port reset shall clear the interrupt register, the waiting codes and the timers. | 5.5.7.1e |

## 3. Error conditions

| Condition | Response |
| --- | --- |
| Received broadcast code of type 0b01 or 0b11, or of a disabled service | Discarded, `Ev_BcIgnored` |
| Received time-code with a value other than register + 1 | Register updated, no indication, `Ev_TcInvalid` |
| Interrupt request within the minimum interval or while waiting | Discarded, `Ev_IntReqDiscarded` |
| Acknowledgement request in interrupt mode | Interrupt register bit cleared, no code, `Ev_AckReqDiscarded` |
| Acknowledgement code received in interrupt mode | Discarded, `Ev_BcIgnored` |
| Indication FIFO full | Indication discarded, `Ev_IndOverflow` |
| Double error in a FIFO | Request or indication discarded, ECC event |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `TimeCodes_g` | true | boolean | Time-code service |
| `Interrupts_g` | true | boolean | Distributed interrupt service |
| `IntTimerWidth_g` | 16 | 1 to 31 | Width of the minimum interval and acknowledgement delay counters in ticks |

| Configuration input | Description |
| --- | --- |
| `Cfg_AckMode` | '1': interrupt with acknowledgement mode, '0': interrupt mode |
| `Cfg_IntTick` | Tick of the interrupt timers in `LinkClk` cycles (0 is treated as 1) |
| `Cfg_IntHoldoff` | Minimum interval between two interrupt codes of one identifier, in ticks |
| `Cfg_AckDelay` | Minimum delay between a received interrupt code and its acknowledgement code, in ticks |

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 5.6.4.3b, 5.6.4.4c | The register holds the last value requested for sending (the time-code master loads it with the value for sending) or received |
| 5.6.5.4c, d | The node enforces the minimum interval by discarding a too early request, as a routing switch would discard the code; the interval is a configuration value because it depends on the network |
| 5.6.5.6e, f | The minimum delay is enforced by holding the acknowledgement code; the maximum delay (5.6.5.6f) depends on the host and is not checked |
| 5.6.5.4b | Several waiting interrupt codes are sent with the highest identifier first |
| 5.5.9 | A code discarded by the Data Link layer outside Run does not start the minimum interval |
