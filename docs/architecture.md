# OpenWire Architecture

Version 0.1. This file is the reference for the architecture and is versioned with the code.

## 1 Purpose, scope and references

This document defines the architecture of OpenWire, a SpaceWire port with a node interface. Together with
ECSS-E-ST-50-12C Rev.1 it is the complete basis for the implementation: it fixes the building blocks, their
interfaces, the ECSS requirements each block owns and the Open Logic entities each block is built from.

### In scope

- Encoding layer: character encoding and decoding, serialisation, Data-Strobe encoding and decoding, first Null,
  Null detection, parity, ESC and disconnect errors, data signalling rates.
- Data Link layer: transmit and receive FIFOs, flow control, sending priority, link state machine, link error
  recovery, broadcast code service.
- Network layer of a node with one end-point: packet service, time-code service with a time-code register,
  distributed interrupt service in interrupt mode and in interrupt with acknowledgement mode.
- Management Information Base (MIB) with all management parameters of a node and an AXI4-Lite register interface.
- The interface to the line drivers and receivers of the Physical layer (data, strobe and enable signals), clocking,
  reset, fault tolerance and the verification architecture.

### Out of scope

- The routing switch: routing, path and logical addressing, group adaptive routing, multicast, the time-code and
  interrupt relay functions of a routing switch and its management parameters (ECSS 5.6.4.6, 5.6.4.7, 5.6.5.5,
  5.6.5.7, 5.6.8, 5.6.9, 5.7.2c, d, 5.7.6b).
- Cables, connectors, cable assemblies, PCB tracks and the electrical properties of the line drivers and receivers
  (ECSS 5.3.2 to 5.3.6). They are properties of the I/O buffers, the board and the harness; section 7.5 states what
  the target has to provide.
- The alternative LinkDisabled behaviour of ECSS 5.5.7.8, a permission for devices of the previous issue of the
  standard.

### Target technology

OpenWire contains no vendor code. The receiver samples the data and strobe signals with the port clock, the
transmitter derives the bit rate from the port clock with an integer divider, and every RAM and clock domain crossing
is an Open Logic entity. The port therefore runs on any FPGA whose I/O buffers provide LVDS (or LVTTL inside a unit,
ECSS 5.3.6.1b); the I/O buffers are instantiated by the design that integrates the port.

### Project

OpenWire is an open SpaceWire implementation that is based on the Open Logic VHDL Library. The code lives in
[open-space-hdl/openwire](https://github.com/open-space-hdl/openwire) under the PSI HDL Library License, Version 1.0,
the licence of Open Logic. Open Logic is pinned to `feature/fault-tolerant-all-entities` of rustyqt/open-logic
(4990f33e).

### References

| ID | Document | Version used |
| --- | --- | --- |
| \[ECSS\] | ECSS-E-ST-50-12C Rev.1, SpaceWire: Links, nodes, routers and networks | 15 May 2019 |
| \[OLO\] | [Open Logic, branch feature/fault-tolerant-all-entities](https://github.com/rustyqt/open-logic/tree/feature/fault-tolerant-all-entities) | 4990f33e |

### Conventions

- Requirement references are ECSS clause numbers with the requirement letter, for example ECSS 5.5.4e. A range such as
  5.5.7.2 to 5.5.7.7 means all requirements of those clauses.
- Coding conventions: those of Open Logic (naming, two-process style, synchronous high-active resets, VSG rules), entity
  prefix `owr_`, VHDL library `openwire`; see [conventions.md](conventions.md).
- "FT" (fault-tolerant) means the Open Logic `olo_ft_*` entities: SECDED ECC on every RAM, TMR on every clock domain
  crossing.

| Term | Meaning |
| --- | --- |
| N-Char | Data character, EOP or EEP (ECSS 3.2.78) |
| L-Char | Link character: FCT or Null (ECSS 3.2.64) |
| BC | Broadcast code: time-code or distributed interrupt code (ECSS 3.2.6) |
| FCT | Flow control token (ECSS 5.4.3.2c) |
| LSM | Link state machine (ECSS 5.5.7) |
| IID | Interrupt identifier (ECSS 3.2.55) |
| SEU | Single event upset |

## 2 SpaceWire functional overview

A SpaceWire port implements four protocol layers and a management information base (ECSS 5.2.1). OpenWire covers every
row of the table below that belongs to a node.

| Layer | Function | ECSS clauses |
| --- | --- | --- |
| Network | Packets, N-Char interleaving | 5.6.2, 6.1.1 |
| Network | Broadcast codes, priority of broadcast codes, discarding of unknown types | 5.6.3, 6.2.2 |
| Network | Time-codes: time-code register, valid time-code, time-code master | 5.6.4.1 to 5.6.4.5, 5.6.4.8, 5.6.4.9, 6.1.2 |
| Network | Distributed interrupts in a node: interrupt and acknowledgement codes, interrupt modes | 5.6.5.1 to 5.6.5.4, 5.6.5.6, 6.1.3 |
| Network | Nodes and node management parameters | 5.6.6, 5.6.7 |
| Network | Routing switch, routing, relaying of time-codes and interrupts | 5.6.4.6, 5.6.4.7, 5.6.5.5, 5.6.5.7, 5.6.8, 5.6.9 |
| Data Link | Interfaces to the Network and Encoding layers, management interface | 5.5.2, 5.5.3 |
| Data Link | Flow control with FCTs, credit errors | 5.5.4, 5.5.5 |
| Data Link | Sending priority of broadcast codes, FCTs, N-Chars and Nulls | 5.5.6 |
| Data Link | Link state machine (ErrorReset to Run), port reset | 5.5.7 |
| Data Link | Link error recovery, accepting broadcast codes for sending | 5.5.8, 5.5.9 |
| Encoding | Serialisation, character and control code encoding, parity | 5.4.2, 5.4.3 |
| Encoding | Data-Strobe encoding and decoding, first Null, Null detection | 5.4.4 to 5.4.6 |
| Encoding | Parity error, disconnect, ESC error | 5.4.7 to 5.4.9 |
| Encoding | Data signalling rates, link speed | 5.4.10, 5.4.11 |
| Physical | Line drivers and receivers, Data-Strobe skew, enables | 5.3.6 to 5.3.8, 6.4 |
| MIB | Configuration, control and status parameters, set and get service | 5.7, 6.5 |

Three properties of the standard shape the architecture more than any single feature:

- **The parity bit of a character covers the previous character** (ECSS 5.4.3.4b). A character is only correct when
  the parity bit of the next character has been checked, and only characters without a parity error may be passed to
  the Data Link layer (ECSS 5.4.2c). The receiver therefore holds every character until the next one has been checked.
- **Every receive condition of the link state machine is an event**: an FCT, N-Char or broadcast code received outside
  the Run state is an error, so the receiver reports each decoded character as a one-cycle event, never as a level.
- **The link error recovery acts on both FIFOs**: the remainder of the packet being sent is discarded from the
  transmit FIFO and an EEP is written to the receive FIFO (ECSS 5.5.8.4). Both FIFOs are part of the Data Link layer,
  next to the flow control that depends on their fill levels.

## 3 Design drivers

| Driver | Consequence |
| --- | --- |
| Use in space: single event upsets in RAMs, registers and clock domain crossings | SECDED ECC on every FIFO, TMR synchronisers on every crossing, state machines with a recovery state, an EDAC monitor in the MIB (P5) |
| Technology independence | A sampling receiver and an integer bit-rate divider in the port clock domain; no vendor primitive (P10) |
| Integration | AXI4-Stream user ports, one AXI4-Lite register file, independent user and management clocks (P7) |
| Verifiability | Every block is verified through its ports, with an independent character-level model of the far end (P8, section 9) |
| Reuse | Every generic function comes from Open Logic; custom logic is limited to the SpaceWire protocol functions (P9) |

## 4 Design goals

| Goal | Implementation |
| --- | --- |
| Defined handshakes between blocks | Every internal data path is a valid / ready stream or a stream of one-cycle events (P2) |
| Correct state semantics | Received conditions are one-cycle events with a defined source; every register has a specified reset value (P4) |
| One protocol function per block | A block implements one ECSS function; no clause is owned by two blocks (P1) |
| Few, proven clock domain crossings | Three clock domains, every crossing an Open Logic FT entity (P3) |
| Fault tolerance | FT entities for all FIFOs and crossings, state machines with a recovery state, contained double errors (P5) |
| One management interface | All parameters in a register file behind one AXI4-Lite port (P7) |
| Tests independent of the design hierarchy | Tests observe only ports and the MIB (section 9) |

## 5 Design principles

| ID | Principle | Rule for the implementation |
| --- | --- | --- |
| P1 | One protocol function per block | A block implements one ECSS function (a clause or a state machine). Its specification names the clauses it owns; no clause is owned by two blocks. |
| P2 | Streams everywhere | Every data path between blocks is a valid / ready stream (Open Logic AXI4-Stream conventions) or, where the receiver can never be slower than the source, a valid-only stream of events. |
| P3 | Few clock domains, proven crossings | Three domains (section 6). Every crossing is built from Open Logic FT entities: `olo_ft_fifo_async` for data, `olo_ft_cc_bits` for levels, `owr_cc_pulse` (a handshake over `olo_ft_cc_bits`) for events, `olo_ft_cc_reset` for resets. |
| P4 | Explicit state semantics | An ECSS "received" condition is a one-cycle event from the block that decodes it. Every state register has a specified reset value. Resets are synchronous and high-active inside every block; `olo_base_reset_gen` brings the reset into each domain. Port reset is a synchronous command. |
| P5 | Fault tolerance by construction | All FIFOs are `olo_ft_fifo_*` (SECDED ECC), all crossings are TMR. State machines have a defined recovery state (D8). ECC events are counted in the MIB; a double error is contained (EEP or discarded code) and never passed on as valid data. |
| P6 | Optional by generics | Time-codes and distributed interrupts are generics (ECSS 5.6.4.1a, 5.6.5.1a); a disabled feature is removed at elaboration and its received codes are ignored. |
| P7 | One management interface | All management parameters of ECSS 5.7 live in one register file behind one AXI4-Lite port, generated from a single register description (VHDL package, documentation, C header). |
| P8 | Verifiable in isolation | Each block has a specification and a unit testbench that drives only its ports. Layer and core benches connect real blocks; the far end of the link is a character-level model written independently of the RTL. |
| P9 | Reuse before design | A function available in Open Logic (FIFO, crossing, synchroniser, arbiter, AXI4-Lite slave, ECC monitor) is instantiated, not rewritten. |
| P10 | No vendor code | The port has no vendor primitive; the I/O buffers are outside the port. |

## 6 Architecture overview

OpenWire follows the ECSS protocol stack one to one: the Network layer of a node, the Data Link layer with the
transmit and receive FIFOs, the Encoding layer and the interface to the line drivers and receivers, with the MIB
reaching every layer.

```text
             UserClk                         |                 LinkClk                                  |  MgmtClk
                                             |                                                          |
 S_Pkt ----------------------------------> [DL-1 TX FIFO] --> DL-5 TX scheduler --> EN-1 transmitter --> Spw_DOut/SOut
 M_Pkt <---------------------------------- [DL-2 RX FIFO] <-- DL-6 RX handler <---- EN-2 receiver <---- Spw_DIn/SIn
                                             |                  |  ^      ^ DL-4 flow control   ^        |
 S_Tc, S_Int, S_IntAck --> NI-4 [req FIFO] ----> NI-2 TC   ---> NI-4 BC arbiter     DL-3 LSM     EN-3    |
 M_Tc, M_Int, M_IntAck <-- NI-4 [ind FIFO] <---- NI-3 INT  <--- (received BCs)      DL-7 recovery loopback|
                                             |                                                          |
                                             |      MG-1 register file  <-- [req FIFO] <-- MG-2 bridge <-- AXI4-Lite
                                             |      MG-3 EDAC monitor   --> [rsp FIFO] --> MG-2 bridge --> (read data)
```

The transmit path runs from the packet port through the transmit FIFO, the scheduler and the transmitter to the
data and strobe outputs; the receive path runs back from the receiver through the receive handler and the receive FIFO.
The FIFOs in brackets are the only data crossings between the clock domains.

### Architecture decisions

| ID | Decision | Reason |
| --- | --- | --- |
| D1 | The receiver samples data and strobe with the port clock (one sample per clock cycle) after a synchroniser (two stages by default) and recovers a bit on every change of Data XOR Strobe | Technology independent; tolerant of simultaneous transitions (ECSS 5.4.4f): a simultaneous transition loses two bits, which the parity check detects |
| D2 | The transmitter shifts one bit per bit period of an integer number of port clock cycles: the initial divider gives 10 Mb/s from the port clock frequency, the run divider is the link speed parameter | Technology independent; the bit rate is exact and free of jitter |
| D3 | The receiver passes a character to the Data Link layer only after the parity bit of the next character has been checked | ECSS 5.4.2c with the parity coverage of ECSS 5.4.3.4b |
| D4 | The packet ports carry one N-Char per beat: a beat with `TLast` = '1' is the end of packet marker (`TData(0)` = '0' EOP, '1' EEP) and carries no data byte | Packets of zero data characters (ECSS 5.6.2.1d) and EEPs are represented without a sideband; the beat count equals the N-Char count of the flow control |
| D5 | The transmit FIFO and the receive FIFO of ECSS 5.2.8 are the crossings between `UserClk` and `LinkClk` | One buffer and one crossing per direction |
| D6 | The register file is in `LinkClk`; the AXI4-Lite slave in `MgmtClk` forwards every access through one FT FIFO and receives the read data through a second one | All MIB semantics (sticky flags, counters, commands) are in the domain of the protocol; a read always returns the current value and follows every earlier write |
| D7 | The Network layer functions of the node (time-code register, interrupt registers and timers, broadcast code priority) are in `LinkClk`; requests and indications of the user ports cross through one FT FIFO per direction | The priority of ECSS 5.6.3d acts on pending codes in the domain of the Data Link layer; one crossing per direction |
| D8 | The protocol state machines have a defined recovery state, without TMR: the `when others` branch leads to it from an illegal state where the synthesis tool implements the state machine safe, and the reset input and the port reset restart it from any state | TMR stays where Open Logic provides it (the crossings); a state machine recovers through its recovery state and the link protocol |
| D9 | A double error read from a FIFO is contained: an N-Char becomes an EEP followed by the discard of the rest of the packet, a broadcast request or indication is discarded, a register access or response is dropped (the read then ends with SLVERR after the read timeout) | Corrupted data is never passed on as valid (P5) |

### Clock domains

| Domain | Clocked blocks | Typical frequency |
| --- | --- | --- |
| `LinkClk` | Encoding layer, Data Link layer, Network layer functions, MIB register file and EDAC monitor | 50 to 200 MHz. The maximum receive data signalling rate is close to the clock frequency (section 7.4); 10 Mb/s needs a frequency within 10 % of a multiple of 10 MHz |
| `UserClk` | User side of the transmit and receive FIFOs and of the broadcast FIFOs | Any |
| `MgmtClk` | AXI4-Lite slave and the bus side of the register bridge | Any |

The three clocks may be the same clock; every crossing works for any frequency ratio.

### Crossings

| Where | Signals | Open Logic entity |
| --- | --- | --- |
| Transmit FIFO, receive FIFO | N-Chars (9 bit) | `olo_ft_fifo_async` (the crossing FIFO is the ECSS FIFO) |
| Broadcast requests, broadcast indications | Kind (2 bit) and value (6 bit) | `olo_ft_fifo_async` |
| Register bridge | Requests (address, data, byte enables, read flag), read data | `olo_ft_fifo_async` |
| ECC events of FIFOs read in `UserClk` or `MgmtClk`, ECC injection commands to write sides in those domains | Events | `owr_cc_pulse`: two-phase handshake over `olo_ft_cc_bits`, TMR registers |
| Interrupt output of the MIB | Level from `LinkClk` to `MgmtClk` | `olo_ft_cc_bits` |
| Port reset | Reset of both FIFO sides | Inside `olo_ft_fifo_async` (`olo_ft_cc_reset`) |
| Reset input | Reset per domain | `olo_base_reset_gen` |

### Internal interfaces

| Interface | Between | Payload | Protocol |
| --- | --- | --- | --- |
| Packet stream | User and transmit / receive FIFO | One N-Char per beat: `TData` 8 bit, `TLast` = end of packet marker (D4) | AXI4-Stream |
| Broadcast service streams | User and NI-4 | Time-code value (6 bit), interrupt identifier (5 bit) per request or indication | AXI4-Stream |
| N-Char stream | FIFOs and DL-5 / DL-6 | 9 bit: flag (end of packet marker) and 8 bit data | Valid / ready |
| Broadcast code stream | NI-4 and DL-5 / DL-6 | 8-bit broadcast code (type and value) | Valid / ready (transmit), valid (receive) |
| Transmit character | DL-5 and EN-1 | Character kind (Null, FCT, data, EOP, EEP, broadcast code) and 8 bit data; presented continuously, taken by a one-cycle acknowledge at the character boundary | Valid / ready with valid always set |
| Receive character | EN-2 and the Data Link blocks | Character kind and 8 bit data; error events (parity, ESC, disconnect), gotNull level | Valid (one-cycle events) |
| Encoding control | DL-3 and EN-1 / EN-2 | Transmit Enable, Receive Enable, run rate select | Levels |
| Data and strobe | EN-1 / EN-2 and the I/O buffers | `Spw_DOut`, `Spw_SOut`, `Spw_DIn`, `Spw_SIn`, driver and receiver enables | Single-ended logic signals |
| Register bus | MG-2 and the user | ECSS 5.7 parameters | AXI4-Lite (`olo_axi_lite_slave`) |

### Reset

The asynchronous reset input is brought into each clock domain by `olo_base_reset_gen`; inside the blocks all resets
are synchronous and high-active (Open Logic convention). Port reset (ECSS 5.5.7.1e) is a MIB command in `LinkClk`: it
clears both FIFOs (the reset input of the `LinkClk` side of an `olo_ft_fifo_async` resets both sides), moves the link
state machine to ErrorReset and the link error recovery state machine to Normal, sets the time-code register to zero
(ECSS 5.6.4.3d) and clears the pending broadcast codes and the interrupt registers. It does not change the
configuration registers.

## 7 Building block specifications

The port has 19 building blocks in five groups. Each block lists its responsibility, the Open Logic entities it is
built from and the ECSS requirements it owns (P1: no clause is owned twice).

### 7.1 Network layer

| ID | Block | Responsibility | Open Logic | ECSS |
| --- | --- | --- | --- | --- |
| NI-1 | Packet port | AXI4-Stream N-Char ports of the end-point (D4); packets are passed through unchanged | none (FIFO ports) | 5.2.2, 5.6.2, 5.6.6, 6.1.1 |
| NI-2 | Time-code | Time-code register (reset to zero by port reset), TIME-CODE.request (register loaded with the value sent), valid time-code check, TIME-CODE.indication of valid time-codes, invalid time-codes counted | none (register) | 5.6.4.1 to 5.6.4.5, 5.6.4.8, 5.6.4.9, 6.1.2 |
| NI-3 | Distributed interrupts | Interrupt register of active interrupts, interrupt mode and interrupt with acknowledgement mode, minimum interval between two interrupt codes of one IID, minimum delay before an acknowledgement, requests and indications | `olo_base_arb_prio` | 5.6.5.1 to 5.6.5.4, 5.6.5.6, 6.1.3 |
| NI-4 | Broadcast code service | Request and indication FIFOs to `UserClk`, priority time-code before acknowledgement before interrupt, decoding of received codes by type, discarding of types 0b01 and 0b11 | `olo_ft_fifo_async`, `olo_base_arb_prio` | 5.6.3 |

### 7.2 Data Link layer

| ID | Block | Responsibility | Open Logic | ECSS |
| --- | --- | --- | --- | --- |
| DL-1 | Transmit FIFO | N-Chars from the user until they are sent; `UserClk` to `LinkClk` crossing; cleared by port reset | `olo_ft_fifo_async` | 5.2.8b |
| DL-2 | Receive FIFO | Received N-Chars until the user reads them; `LinkClk` to `UserClk` crossing; cleared by port reset | `olo_ft_fifo_async` | 5.2.8c |
| DL-3 | Link state machine | States ErrorReset, ErrorWait, Ready, Started, Connecting and Run with all exit conditions in the order of the standard, timers of 6.4 us and 12.8 us, gotFCT, Transmit Enable and Receive Enable, port reset | none (state machine) | 5.2.8e, 5.5.2h, i, 5.5.3a, 5.5.7.1 to 5.5.7.7, 6.3.1.3, 6.3.2.3 |
| DL-4 | Flow control manager | Transmit and receive credit counters (0 to 56), FCT request when the receive FIFO has room for eight more N-Chars, credit errors | none (counters) | 5.2.8d, 5.5.4, 5.5.5 |
| DL-5 | Transmit scheduler | Character for the transmitter by state and priority (broadcast code, FCT, N-Char, Null), Sent Null and Sent FCT, broadcast code slot discarded outside Run, discarding of the packet remainder during recovery | none | 5.5.2a, b, e, 5.5.6, 5.5.9, 6.2.1.2, 6.2.2.2 |
| DL-6 | Receive handler | N-Chars to the receive FIFO and broadcast codes to the Network layer in Run, EEP after an error in a packet | none | 5.5.2c, d, f, g, 6.2.1.3, 6.2.2.3 |
| DL-7 | Link error recovery | Normal and Recovery states, recovery actions of DL-5 and DL-6, cause of the error | none (state machine) | 5.5.8 |

### 7.3 Encoding layer

| ID | Block | Responsibility | Open Logic | ECSS |
| --- | --- | --- | --- | --- |
| EN-1 | Transmitter | Character and control code encoding with odd parity, serialisation, Data-Strobe encoding, first Null, controlled reset of data and strobe, initial and run data signalling rates | none | 5.2.8f, 5.4.2a, e.1, 5.4.3 (encoding), 5.4.4a to e, 5.4.5, 5.4.10, 6.3.1 |
| EN-2 | Receiver | Data-Strobe decoding, de-serialisation, character decoding, Null detection and gotNull, parity error, ESC error, disconnect, characters passed only after the parity check | `olo_intf_sync` | 5.2.8g, 5.4.2b to d, e.2, f, 5.4.3 (decoding), 5.4.4f, 5.4.6 to 5.4.9, 6.3.2 |
| EN-3 | Port loopback | Loops data and strobe of the transmitter back to the receiver (MIB) | none | 5.6.10f |

### 7.4 Receiver timing

The receiver recovers a bit when Data XOR Strobe changes between two samples. Two transitions are resolved when a
sampling edge lies between them, so the minimum tolerated separation between signal edges (MinsepIN, ECSS 5.3.7.2j)
is one `LinkClk` period plus the setup and hold window of the input flip-flops. With `LinkClk` = 200 MHz, MinsepIN is
5 ns plus the flip-flop window; the maximum receive data signalling rate follows from ECSS 5.3.7.2l with the skew and
jitter of the transmitter and the cable assembly.

### 7.5 Physical layer interface

| ID | Block | Responsibility | Open Logic | ECSS |
| --- | --- | --- | --- | --- |
| PH-1 | Line driver and receiver interface | Single-ended data and strobe of the transmitter and receiver, line driver enable and line receiver enable for the I/O buffers of the target; the LVDS buffers (or LVTTL inside a unit), the board and the harness belong to the target | none | 5.2.5, 5.2.8h, i, 5.3.6, 5.3.7, 6.4 |

### 7.6 Management

| ID | Block | Responsibility | Open Logic | ECSS |
| --- | --- | --- | --- | --- |
| MG-1 | Register file | All configuration, control and status parameters of the node in `LinkClk`, generated from one register description (`hdl/owr_mib/regs/owr_regs.yml`, `tools/regmap.py`); commands for port reset, time-codes and interrupts | none (register file) | 5.2.6, 5.3.8, 5.4.11, 5.5.3b, 5.6.7, 5.7.1 to 5.7.6 (node), 6.5 |
| MG-2 | Register bridge | AXI4-Lite slave in `MgmtClk`; every write and read crosses to MG-1 through one FT FIFO, read data returns through another | `olo_axi_lite_slave`, `olo_ft_fifo_async` | none (transport of 6.5 for MG-1) |
| MG-3 | EDAC monitor | Counts the SEC and DED events of every FT FIFO, raises an interrupt, injects single and double errors for tests | `olo_ft_ecc_monitor`, `olo_ft_cc_bits`, `olo_ft_cc_reset` (`owr_cc_pulse`) | none (fault tolerance, P5) |
| MG-4 | Clock and reset | Reset per domain, port reset | `olo_base_reset_gen` | none owned (port reset of 5.5.7.1e for DL-3) |

## 8 Open Logic usage

| Open Logic entity | Used in | Purpose |
| --- | --- | --- |
| `olo_ft_fifo_async` | DL-1, DL-2, NI-4, MG-2 | ECSS FIFOs and every data crossing; ECC on the buffer RAM, TMR on the pointer and reset crossings |
| `olo_ft_cc_bits` | MG-1, MG-3 | Interrupt output to `MgmtClk`; request and acknowledge levels of `owr_cc_pulse` (ECC events and injection commands across domains) |
| `olo_ft_cc_reset` | MG-3 | Coupled resets of both sides of `owr_cc_pulse` |
| `olo_ft_ecc_monitor` | MG-3 | SEC and DED counters per FIFO, DED sticky flags |
| `olo_intf_sync` | EN-2 | Synchroniser of the asynchronous data and strobe inputs |
| `olo_base_arb_prio` | NI-3, NI-4 | Priority of broadcast requests and of pending interrupt codes |
| `olo_axi_lite_slave` | MG-2 | AXI4-Lite access to the register file |
| `olo_base_reset_gen` | MG-4 | Reset per clock domain |

### Gaps in Open Logic

| Gap | Resolution in this architecture |
| --- | --- |
| No SpaceWire codec | EN-1 and EN-2 are custom blocks |
| No FT handshake crossing for register accesses | The register bus crosses through two `olo_ft_fifo_async` (D6) |
| No TMR helper for protocol state machines | Recovery state of every state machine (D8) |
| `olo_ft_cc_pulse` is built from a set/reset latch per copy (a transparent latch in the FPGA, untimed, gate and data both follow the input pulse) | `owr_cc_pulse`: latch-free two-phase handshake over `olo_ft_cc_bits` with triplicated registers |

## 9 Verification architecture

The port is verified with VUnit and UVVM in a seven-phase module workflow (requirements, architecture, verification
plan, RTL, testbenches, verification, integration; see [conventions.md](conventions.md)). Every building block of
section 7 belongs to a module with its own specification, verification plan, testbench and verification report; core
tests cross the seams between the modules. Every test case names the requirements it verifies, and every requirement
names its ECSS clauses, so the traceability matrix of section 10 is checked by `tools/compliance.py`.

| Level | Scope | Bench | Checks |
| --- | --- | --- | --- |
| Unit | One block or one layer (for example EN-2, DL-3) | `<entity>_th.vhd` (clocks, DUT, models) and `<entity>_tb.vhd` (VUnit runner, one `run("test_...")` per test of the verification plan) | UVVM checks and scoreboards, directed tests at the block ports |
| Layer | Encoding and Data Link layer of one port against a far-end model at character level | Data-Strobe model of the far end: sends any character sequence (also illegal ones) with a configurable bit rate, injects parity errors, simultaneous transitions and disconnects; decodes and logs every character the port sends | Character order, timing of the state machine, flow control, error recovery |
| Core | Two cores back to back through a link model, and one core against the far-end model | AXI4-Stream VVCs on the packet ports, AXI4-Lite VVC on the MIB, link model with propagation delay, bit errors and disconnects | Packet integrity and order, time-codes and interrupts end to end, MIB programming sequences, recovery after every injected error, throughput |

### Framework

- VUnit (`run.py`) discovers and runs every test and is the CI regression. UVVM supplies the verification building
  blocks: AXI4-Stream and AXI4-Lite VVCs, alert and log handling, `check_value` / `await_value`, randomisation and
  functional coverage.
- The far-end model and the link model are behavioural VHDL in `tb/`. They encode and decode characters with their
  own implementation of ECSS 5.4.3 and 5.4.4, in continuous time and independent of the sampling clock of the port.
- Simulator: GHDL for every test; QuestaSim for code coverage.

### Rules

- Tests observe ports and the MIB only (P8).
- A failed check fails the test; a test cannot pass with a failed step.
- Negative tests inject the fault from the bench (parity error, ESC error, disconnect, credit violation, double error
  through the `ErrInj` ports) and expect the alert or the status; never from an RTL mutation.
- Every commit passes the full regression.

## 10 Requirement traceability matrix

Every ECSS clause in the scope of section 1 has exactly one owner block. "First verified at" names the lowest
verification level at which the clause can be fully checked. The [compliance matrix](compliance.md), generated from this
table, the module specifications and the verification plans, lists the requirements and test cases of every clause.

| ECSS clause | Title | Owner | Also involved | First verified at |
| --- | --- | --- | --- | --- |
| 5.2.1 | Protocol stack | Core | all blocks | Core |
| 5.2.2 | Network layer | NI-1 | NI-2, NI-3 | Core |
| 5.2.3 | Data Link layer | DL-5 | DL-3, DL-6 | Layer |
| 5.2.4 | Encoding layer | EN-1 | EN-2 | Unit |
| 5.2.5 | Physical layer | PH-1 |  | Core |
| 5.2.6 | Management Information Base | MG-1 | MG-2 | Unit |
| 5.2.8 | SpaceWire port architecture | Core | DL-1 to DL-4, EN-1, EN-2, PH-1 | Core |
| 5.3.2 to 5.3.5 | Cables, connectors, cable assemblies, PCB tracks | Out of scope (board and harness) |  |  |
| 5.3.6 | Line drivers and receivers | PH-1 | target I/O buffers | Target |
| 5.3.7 | Data-Strobe skew | PH-1 | EN-2 (MinsepIN) | Unit |
| 5.3.8 | Physical layer management parameters | MG-1 | PH-1 | Core |
| 5.4.2 | Serialisation and de-serialisation | EN-1 (transmit), EN-2 (receive) |  | Unit |
| 5.4.3 | Character and control code encoding | EN-1 (encode), EN-2 (decode) |  | Unit |
| 5.4.4 | Data-Strobe encoding and decoding | EN-1 (a to e), EN-2 (f) |  | Unit |
| 5.4.5 | First Null | EN-1 |  | Unit |
| 5.4.6 | Null detection | EN-2 |  | Unit |
| 5.4.7 | Parity error | EN-2 |  | Unit |
| 5.4.8 | Disconnect | EN-2 |  | Unit |
| 5.4.9 | ESC error | EN-2 |  | Unit |
| 5.4.10 | Data signalling rate | EN-1 | EN-2, MG-1 | Unit |
| 5.4.11 | Encoding layer management parameters | MG-1 | EN-1 | Core |
| 5.5.2 | Data Link layer interfaces | DL-5 (a, b, e), DL-6 (c, d, f, g), DL-3 (h, i) | EN-1, EN-2 | Layer |
| 5.5.3 | Data Link layer management interface | DL-3 (a), MG-1 (b) | DL-4 | Layer |
| 5.5.4 | Flow control | DL-4 | DL-5, DL-6 | Layer |
| 5.5.5 | Flow control errors | DL-4 | DL-3 | Layer |
| 5.5.6 | Sending priority | DL-5 |  | Layer |
| 5.5.7.1 to 5.5.7.7 | Link initialisation behaviour | DL-3 | DL-1, DL-2 | Layer |
| 5.5.7.8 | Alternative behaviour when disabled asserted | Not implemented (permission) |  |  |
| 5.5.8 | Link error recovery | DL-7 | DL-5, DL-6 | Layer |
| 5.5.9 | Accepting broadcast codes for sending | DL-5 |  | Layer |
| 5.6.2 | SpaceWire packets | NI-1 | DL-5, DL-6 | Core |
| 5.6.3 | Broadcast codes | NI-4 | NI-2, NI-3 | Unit |
| 5.6.4.1 to 5.6.4.5, 5.6.4.8, 5.6.4.9 | Time-codes in a node | NI-2 | NI-4 | Unit |
| 5.6.4.6, 5.6.4.7 | Time-codes in a routing switch | Out of scope (no routing switch) |  |  |
| 5.6.5.1 to 5.6.5.4, 5.6.5.6 | Distributed interrupts in a node | NI-3 | NI-4 | Unit |
| 5.6.5.5, 5.6.5.7 | Relaying interrupts in a routing switch | Out of scope (no routing switch) |  |  |
| 5.6.6 | SpaceWire nodes | NI-1 | NI-2, NI-3 | Core |
| 5.6.7 | Node management parameters | MG-1 |  | Unit |
| 5.6.8, 5.6.9 | Routing, routing switch management parameters | Out of scope (no routing switch) |  |  |
| 5.6.10 | SpaceWire network | EN-3 (f) | Core | Core |
| 5.7 | Management information base | MG-1 | MG-2 | Unit |
| 6.1.1 | Packet service interface | NI-1 |  | Core |
| 6.1.2 | Time-code service interface | NI-2 | NI-4 | Unit |
| 6.1.3 | Distributed interrupt service interface | NI-3 | NI-4 | Unit |
| 6.2.1 | N-Char service interface | DL-5 (send), DL-6 (read) | DL-1, DL-2 | Layer |
| 6.2.2 | Broadcast code service interface | DL-5 (request), DL-6 (indication) | NI-4 | Layer |
| 6.3.1 | Encoding service interface | EN-1 | DL-3 | Unit |
| 6.3.2 | Decoding service interface | EN-2 | DL-3 | Unit |
| 6.4 | Physical layer service interface | PH-1 |  | Core |
| 6.5 | MIB service interface | MG-1 | MG-2 | Unit |

## 11 Development plan

1. Foundations: repository, common package, verification components (far-end and link models), regression and CI.
2. Encoding layer (EN-1 to EN-3) with unit tests against the far-end model.
3. Data Link layer (DL-1 to DL-7) with layer tests against the far-end model.
4. Network layer (NI-1 to NI-4).
5. MIB (MG-1 to MG-3) with the generated register map.
6. Core top level (MG-4) with core tests of two ports and of a port against the far-end model, the compliance matrix
   and the synthesizability check.
