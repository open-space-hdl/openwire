# owr_core: Verification Plan

## 1. Overview

The core is verified at its ports as a node: two cores A and B with different clocks on a line with a propagation
delay, and core A against the Data-Strobe far-end model, which decodes the line with its own implementation of the
standard. Every test programs the cores through the MIB with the operational sequence of the user guide (link speed,
port control, polling of the link state) and checks packets, broadcast services and status at the user ports and in
the MIB. These tests cross every seam between the modules: packet mapping, broadcast codes between the Network and
Data Link layers, Data Link to Encoding layer, configuration and status between the MIB and all layers, the three
clock domains and the data and strobe lines.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `owr_core_tb` | `owr_core_th`, `owr_core_tb_node` | Core A: LinkClk 100 MHz, UserClk 83.3 MHz, MgmtClk 50 MHz; core B: 125 MHz, 62.5 MHz, 100 MHz; line delay 25 ns, cut and glitch control; far-end model on the line of A (`LinkMode` = '1'); AXI4-Stream VVCs on the packet ports, AXI4-Lite VVCs on the MIBs, logs of the broadcast indications; configuration `no_services` with core B without time-codes and interrupts |

Simulator: GHDL.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_link_startup` (TC-CORE-01) | Identification and clock of both MIBs; both ports wait in Ready; link speed, LinkStart at A, AutoStart at B; both in Run, interrupt on link up, event and counter, credits 56 and 56, no error, driver and receiver enabled | CORE-IF-03, CORE-IF-04, CORE-ST-01, CORE-ST-02, CORE-NI-02 |
| `test_packets` (TC-CORE-02) | 40 packets of 0 to 500 bytes from A to B (EOP and EEP) and 40 from B to A at the same time, full payload compared | CORE-IF-01, CORE-NI-01, CORE-NI-02 |
| `test_time_codes` (TC-CORE-03) | 70 time-codes from the user port of A indicated in order at B; time-code registers; a time-code that is not the next one is counted as invalid at B | CORE-IF-02, CORE-NI-02 |
| `test_interrupts` (TC-CORE-04) | Interrupt with acknowledgement: interrupt from A, acknowledgement from B indicated at A, interrupt registers; interrupts of the MIB; interrupt mode: no acknowledgement code | CORE-IF-02 |
| `test_line_errors` (TC-CORE-05) | Line cut in a packet: both ports restart, the packet arrives truncated with an EEP, the rest is discarded at A, the following packets are complete; cause and counters in the MIB. Glitch on the data line: receive error at B, restart, EEP | CORE-NI-01, CORE-ST-01 |
| `test_port_reset` (TC-CORE-06) | Port reset through the MIB in Run: time-code register zero, the link restarts, packets after the restart | CORE-ST-01 |
| `test_loopback` (TC-CORE-07) | Port loopback: A starts a link with itself and receives its own packets | CORE-LB-01 |
| `test_rates` (TC-CORE-08) | A sends at 100 Mb/s (bit period 1.25 clock periods of B), B at 13.9 Mb/s; packets in both directions | CORE-PH-01 |
| `test_phy_enables` (TC-CORE-09) | Line driver and receiver enables of PORT_CTRL at the core outputs | CORE-PH-02, CORE-IF-04 |
| `test_ecc` (TC-CORE-10) | Double error injected into the transmit FIFO of A: EEP at B, next packet complete, EDAC counters and flags; single error in the receive FIFO of B corrected | CORE-FT-01 |
| `test_throughput` (TC-CORE-11) | 20 packets of 1000 bytes from A at 100 Mb/s and 20 of 600 bytes from B at 62.5 Mb/s at the same time: both at 90 % or more of the data character rate | CORE-PF-01 |
| `test_link_disabled` (TC-CORE-12) | LinkDisabled keeps A in ErrorReset and B in Ready; enabled: Run; LinkDisabled in Run: ErrorReset with the cause LinkDisabled | CORE-ST-01 |
| `test_far_end` (TC-CORE-13) | A against the far-end model: initial bit period 100 ns until Run, seven FCTs, run bit period 40 ns, packets in both directions decoded by the model, time-code of the model indicated | CORE-IF-04, CORE-NI-01, CORE-PH-01 |
| `test_no_services` (TC-CORE-14) | Configuration `no_services`: B ignores time-codes and interrupt codes and reports them | CORE-IF-02 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| CORE-IF-01 | TC-CORE-02 |
| CORE-IF-02 | TC-CORE-03, TC-CORE-04, TC-CORE-14 |
| CORE-IF-03 | TC-CORE-01 |
| CORE-IF-04 | TC-CORE-01, TC-CORE-09, TC-CORE-13 |
| CORE-ST-01 | TC-CORE-01, TC-CORE-05, TC-CORE-06, TC-CORE-12 |
| CORE-ST-02 | TC-CORE-01 |
| CORE-NI-01 | TC-CORE-02, TC-CORE-05, TC-CORE-13 |
| CORE-NI-02 | TC-CORE-01, TC-CORE-02, TC-CORE-03 |
| CORE-PH-01 | TC-CORE-08, TC-CORE-13 |
| CORE-PH-02 | TC-CORE-09 |
| CORE-LB-01 | TC-CORE-07 |
| CORE-FT-01 | TC-CORE-10 |
| CORE-PF-01 | TC-CORE-11 |

## 5. Seams crossed

| Seam | Test cases |
| --- | --- |
| Packet ports to the Data Link FIFOs (NI-1 mapping) | TC-CORE-02, TC-CORE-13 |
| Network layer to Data Link layer (broadcast codes) | TC-CORE-03, TC-CORE-04, TC-CORE-14 |
| Data Link layer to Encoding layer, data and strobe lines | all tests with a link |
| MIB to the layers (configuration, commands, status, events, EDAC) | TC-CORE-01, TC-CORE-05, TC-CORE-06, TC-CORE-09, TC-CORE-10, TC-CORE-12 |
| Three clock domains with different frequencies | all tests |
| Reset of each domain | every test (reset at the start) |
