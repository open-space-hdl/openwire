# owr_core: Specification

## 1. Overview

`owr_core` is the OpenWire core: a SpaceWire port with a node interface (ECSS-E-ST-50-12C Rev.1). It connects the
Network layer (`owr_ni`), the Data Link layer (`owr_dl`), the Encoding layer (`owr_enc`) and the MIB (`owr_mib`),
maps the packet ports onto the N-Chars of the Data Link layer (NI-1) and brings the reset into the three clock
domains (MG-4). The line drivers and receivers (LVDS) are instantiated by the design that integrates the core.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| CORE-IF-01 | The core shall provide a packet transmit and a packet receive port (AXI4-Stream in `UserClk`), one N-Char per beat: a beat with `TLast` = '1' is the end of packet marker (`TData(0)` = '0' EOP, '1' EEP) and carries no data. | 5.2.8a, 5.6.6c, d, e, 6.1.1 |
| CORE-IF-02 | The core shall provide the optional broadcast code transmit and receive interfaces as time-code and distributed interrupt request and indication ports (AXI4-Stream in `UserClk`). | 5.2.8a, 5.6.6f, g, h, i, j |
| CORE-IF-03 | The core shall provide the MIB on an AXI4-Lite port and an interrupt output in `MgmtClk`. | 5.2.6, 5.7.2a, b, 6.5 |
| CORE-IF-04 | The core shall drive data and strobe and the enables of the line driver and line receiver, and receive data and strobe from the line receiver; the LVDS (or LVTTL) buffers of the target are connected to these signals. | 5.2.5, 5.2.8f to i, 5.3.6, 6.4 |

### 2.2 Structure

| ID | Requirement | ECSS |
| --- | --- | --- |
| CORE-ST-01 | The core shall implement the SpaceWire protocol stack of a node: Network layer, Data Link layer, Encoding layer, the interface to the Physical layer and the MIB, with a transmit FIFO, a receive FIFO, a flow control manager, a link state machine, a transmitter and a receiver. | 5.2.1, 5.2.2, 5.2.8 |
| CORE-ST-02 | The core shall bring one asynchronous reset input into the clocks `UserClk`, `LinkClk` and `MgmtClk`; the three clocks may be independent or the same clock. | none |

### 2.3 Function of the node

| ID | Requirement | ECSS |
| --- | --- | --- |
| CORE-NI-01 | Packets shall be transferred between two nodes unchanged and in order, without interleaving of N-Chars of different packets; packets without data characters and packets ending with an EEP shall be transferred. | 5.6.2.1, 5.6.2.2, 6.1.1 |
| CORE-NI-02 | The node shall be a source and a destination of packets, time-codes and distributed interrupts through one end-point. | 5.6.6a, b |
| CORE-PH-01 | The receiver shall accept a far-end data signalling rate with a bit period of at least 1.2 `LinkClk` periods; the transmitter shall send at its own rate, independent of the far end. | 5.3.7.2j, 5.4.10.4a, b |
| CORE-PH-02 | The MIB shall control the enables of the line driver and of the line receiver. | 5.3.8 |
| CORE-LB-01 | With the port loopback the port shall start a link with itself and receive its own packets. | 5.6.10f |
| CORE-FT-01 | A double error in the transmit FIFO shall reach the far end as an EEP, and the following packets shall be transferred unchanged. | none (P5) |
| CORE-PF-01 | With packets of 1000 bytes, the user data rate shall be at least 90 % of the data character rate (8 data bits per 10 bits) in each direction, with traffic in both directions. | none |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `LinkClkFreq_g` | 100.0e6 | 20 MHz to 400 MHz, within 10 % of a multiple of 10 MHz | Frequency of `LinkClk` in Hz |
| `TxFifoDepth_g`, `RxFifoDepth_g` | 64 | Powers of 2, 16 or more | FIFO depths in N-Chars; 64 or more for seven outstanding FCTs |
| `TimeCodes_g`, `Interrupts_g` | true | boolean | Broadcast services |
| `IntTimerWidth_g` | 16 | 1 to 30 | Width of the interrupt timers in ticks |
| `LinkDisabled_g`, `LinkStart_g`, `AutoStart_g` | false | boolean | Reset values of the port control |
| `RunDiv_g` | 1 | 1 to 255 | Reset value of the bit period in Run (`LinkClk` cycles) |
| `SyncStages_g` | 2 | 2 to 4 | Synchroniser stages of data and strobe |
