# owr_mib: Verification Plan

## 1. Overview

The MIB is verified through its AXI4-Lite port with the UVVM AXI4-Lite VVC: every register of the description is read
after reset, written and read back; the status and event inputs are driven by the sequencer and the configuration
outputs, command pulses and injection commands are observed in their clock domains. The register bridge runs with a
management clock faster and slower than the link clock.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `owr_mib_tb` | `owr_mib_th` | `owr_mib` (LinkClk 100 MHz, FIFO depths 64 and 128, LinkStart_g, RunDiv_g = 4), UserClk 83.3 MHz, MgmtClk 166.7 MHz (configurations `mgmt_fast`, `mgmt_slow` with 25 MHz for TC-MG-09), AXI4-Lite VVC, observers |

Simulator: GHDL.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_reset_values` (TC-MG-01) | Every register after reset, generics, reset values of the port control from the generics, unused address reads zero, outputs | MG-RF-06, MG-IF-01, MG-IF-02, MG-RF-01, MG-RF-02, MG-RF-03 |
| `test_config_registers` (TC-MG-02) | Write and read back of every RW register; the configuration outputs follow; read-only registers ignore writes | MG-IF-01, MG-IF-02, MG-RF-01 to MG-RF-05 |
| `test_commands` (TC-MG-03) | Port reset, TIME-CODE.request, DISTRIBUTED_INTERRUPT.request and DISTRIBUTED_INTERRUPT_ACK.request as one-cycle pulses with their values; commands read zero | MG-RF-01, MG-RF-05 |
| `test_status_registers` (TC-MG-04) | Link state, recovery, gotNull, discard, cause, credits, FIFO levels, time-code register, interrupt register | MG-RF-01, MG-RF-05, MG-IF-02 |
| `test_flags` (TC-MG-05) | Every event input sets its flag; link up and down from the link state; acknowledgements per identifier; write one clears only the written bits | MG-RF-07 |
| `test_counters` (TC-MG-06) | Error counters (disconnect saturates at 255), time-code counters, Run entries and recoveries; cleared by a write | MG-RF-07 |
| `test_irq` (TC-MG-07) | Interrupt output follows enabled flags only | MG-RF-08, MG-IF-03 |
| `test_ecc` (TC-MG-08) | ECC events of all four layer FIFOs counted per channel, DED flags, event flags, read and clear, global clear; injection commands arrive in the clock domain of each write side with one or two flipped bits; single error in the register request and response FIFOs corrected; double error: write dropped, read ends with SLVERR (expected alert) | MG-ED-01, MG-ED-02, MG-BR-02 |
| `test_read_after_write` (TC-MG-09) | Configurations `mgmt_fast` and `mgmt_slow`: 50 writes each followed by a read of the value; 20 back-to-back command writes all executed | MG-BR-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| MG-IF-01 | TC-MG-01, TC-MG-02 |
| MG-IF-02 | TC-MG-01, TC-MG-02, TC-MG-04 |
| MG-IF-03 | TC-MG-07 |
| MG-RF-01 | TC-MG-01 to TC-MG-04 |
| MG-RF-02, MG-RF-03 | TC-MG-01, TC-MG-02 |
| MG-RF-04 | TC-MG-02 |
| MG-RF-05 | TC-MG-02, TC-MG-03, TC-MG-04 |
| MG-RF-06 | TC-MG-01 |
| MG-RF-07 | TC-MG-05, TC-MG-06 |
| MG-RF-08 | TC-MG-07 |
| MG-BR-01 | TC-MG-09 |
| MG-BR-02 | TC-MG-08 |
| MG-ED-01, MG-ED-02 | TC-MG-08 |

## 5. Negative tests

| Checker | Test |
| --- | --- |
| Double error in the register request FIFO (write dropped) and response FIFO (read error) | TC-MG-08 |
| Saturation of the counters | TC-MG-06 |
