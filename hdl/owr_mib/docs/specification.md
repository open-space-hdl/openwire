# owr_mib: Specification

## 1. Overview

`owr_mib` is the Management Information Base of OpenWire (ECSS-E-ST-50-12C Rev.1 clauses 5.7 and 6.5): the register
file with all configuration, control and status parameters of a node (MG-1), the bridge from the AXI4-Lite port in
`MgmtClk` to the register file in `LinkClk` (MG-2), and the EDAC monitor of all FIFOs with error injection (MG-3). The
register map is generated from `regs/owr_regs.yml` by `tools/regmap.py` ([register_map.md](register_map.md)).

| Block | Entity | Function |
| --- | --- | --- |
| MG-1 | `owr_mib_regs` | Register file in `LinkClk` |
| MG-2 | `owr_mib_bridge` | AXI4-Lite slave in `MgmtClk`, request and response FIFOs |
| MG-3 | `owr_mib_regs` (`olo_ft_ecc_monitor`), `owr_mib` | EDAC counters, crossings of the ECC events and injection commands |

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| MG-IF-01 | The MIB shall provide an AXI4-Lite slave (8-bit byte address, 32-bit data) for the set parameter and get parameter services; registers are written as 32-bit words. | 5.2.6a, b, c, 5.7.2a, b, 6.5.1, 6.5.2 |
| MG-IF-02 | The MIB shall drive the configuration and control parameters of the Data Link, Encoding and Network layers and of the line drivers and receivers in `LinkClk`, and read their status. | 5.2.6d |
| MG-IF-03 | The MIB shall provide an interrupt output in `MgmtClk`. | none |

### 2.2 Register file (MG-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| MG-RF-01 | The register file shall provide PortReset (command), LinkDisabled, LinkStart and AutoStart, the link state, the error flags disconnect, parity error, ESC error and credit error, the transmit and receive credit counters, the recovery state and the cause of the last error recovery. | 5.5.3a, b, 5.7.5, 5.5.8.4a.5 |
| MG-RF-02 | The register file shall provide the link speed (bit period in the Run state) and show the initial bit period. | 5.4.11, 5.7.4 |
| MG-RF-03 | The register file shall provide the enables of the line driver and of the line receiver. | 5.3.8, 5.7.3 |
| MG-RF-04 | The register file shall provide the port loopback control. | 5.6.10f |
| MG-RF-05 | The register file shall provide the time-code register, the TIME-CODE.request, the interrupt register, the DISTRIBUTED_INTERRUPT.request and DISTRIBUTED_INTERRUPT_ACK.request, the received acknowledgements, the interrupt mode and the interrupt timers. | 5.6.7, 5.7.6a |
| MG-RF-06 | Every register shall have the reset value of the register description; reset values of the port control and the link speed shall be generics, so that a port without software starts the link. | none |
| MG-RF-07 | Sticky flags shall be set by events and cleared by writing one; counters shall saturate and be cleared by any write; an event in the cycle of a clear shall be kept. | none |
| MG-RF-08 | The interrupt output shall be the OR of the error and event flags enabled by the interrupt enable registers. | none |

### 2.3 Register bridge (MG-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| MG-BR-01 | Every write and read accepted on the AXI4-Lite port shall be executed by the register file in the order of acceptance, through an FT FIFO, for any ratio of the clock frequencies; new accesses are held while the FIFO has no room. | 6.5 |
| MG-BR-02 | A request read with a double error shall be dropped (a read then ends with SLVERR after the read timeout); a response with a double error or of an earlier read shall be dropped. | none (P5) |

### 2.4 EDAC (MG-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| MG-ED-01 | The SEC and DED events of the six FIFOs of the port (transmit, receive, broadcast requests and indications, register requests and responses) shall be counted per channel with a DED sticky flag per channel, a read and clear per channel and a global clear; they shall also set the ECC event flags. | none (P5) |
| MG-ED-02 | A command shall inject a single or a double error into the next word written to the selected FIFO, in the clock domain of its write side. | none (P5) |

## 3. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `LinkClkFreq_g` | 100.0e6 | Frequency of `LinkClk` (CLK_FREQ, initial divider, reset value of INT_TICK) |
| `TxFifoDepth_g`, `RxFifoDepth_g` | 64 | Shown in FIFO_DEPTHS |
| `TimeCodes_g`, `Interrupts_g`, `IntTimerWidth_g` | true, true, 16 | Shown in GENERICS; width of INT_HOLDOFF and INT_ACK_DELAY |
| `LinkDisabled_g`, `LinkStart_g`, `AutoStart_g` | false | Reset values of PORT_CTRL |
| `RunDiv_g` | 1 | Reset value of LINK_SPEED.RUN_DIV |
| `ReadTimeoutClks_g` | 1000 | Read timeout of the AXI4-Lite slave in `MgmtClk` cycles |
