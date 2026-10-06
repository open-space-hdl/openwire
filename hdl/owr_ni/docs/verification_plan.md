# owr_ni: Verification Plan

## 1. Overview

The Network layer is verified at its ports: the user ports and the MIB inputs issue requests, a model of the
broadcast slot of the Data Link layer logs the codes passed to it (and can withhold them or discard them as outside
Run), received codes are injected, and the indications are logged. A second instance without time-codes and
distributed interrupts checks the disabled services. The packet service (NI-1) is verified at core level.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `owr_ni_tb` | `owr_ni_th`, `owr_ni_tb_inst` | Instance 1 (`TimeCodes_g`, `Interrupts_g` = true), instance 2 (both false), LinkClk 100 MHz, UserClk 62.5 MHz, model of the broadcast slot, logs of codes and indications, event counters |

Simulator: GHDL.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_tc_send` (TC-NI-01) | Time-code requests of the user port and of the MIB sent; register loaded with the value sent; a waiting request replaced by the next one | NI-TC-02, NI-IF-01, NI-IF-03, NI-IF-04 |
| `test_tc_receive` (TC-NI-02) | Received 6, 8, 9 after 5: two indications and one invalid time-code; register follows; 0 after 63 valid | NI-TC-03, NI-IF-02 |
| `test_tc_port_reset` (TC-NI-03) | Port reset sets the register to zero, 1 is then valid | NI-TC-04 |
| `test_bc_priority` (TC-NI-04) | Waiting time-code, acknowledgement and interrupt passed in this order; simultaneous user requests on the three ports | NI-BC-01, NI-IF-01 |
| `test_bc_types` (TC-NI-05) | Codes of type 0b01 and 0b11 discarded and reported; time-code, interrupt and acknowledgement decoded | NI-BC-02 |
| `test_int_send` (TC-NI-06) | Interrupt code sent; request within the minimum interval and request of a waiting identifier discarded; several waiting codes highest identifier first; a code discarded outside Run does not start the interval | NI-IN-03 |
| `test_int_receive` (TC-NI-07) | Received interrupt codes set the interrupt register and are indicated | NI-IN-04 |
| `test_int_modes` (TC-NI-08) | Interrupt with acknowledgement mode: acknowledgement request clears the register, the code is held for the minimum delay; acknowledgement without a received interrupt sent at once; received acknowledgement indicated. Interrupt mode: no acknowledgement code, request and received acknowledgement discarded | NI-IN-02, NI-IN-05, NI-IN-06 |
| `test_int_timers` (TC-NI-09) | Minimum interval of 5 ticks of 10 cycles measured between two interrupt codes | NI-IN-07 |
| `test_int_port_reset` (TC-NI-10) | Port reset clears the interrupt register, the waiting codes and the timers | NI-IN-08 |
| `test_disabled_services` (TC-NI-11) | Instance 2: received codes ignored, requests discarded | NI-TC-01, NI-IN-01 |
| `test_ind_overflow` (TC-NI-12) | Indication FIFO full: indications lost and reported, the stored ones delivered in order | NI-IF-02 |
| `test_ecc` (TC-NI-13) | Single errors in the request and indication FIFOs corrected, double errors discarded, events counted | NI-BC-03 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| NI-IF-01 | TC-NI-01, TC-NI-04 |
| NI-IF-02 | TC-NI-02, TC-NI-12 |
| NI-IF-03, NI-IF-04 | TC-NI-01 |
| NI-BC-01 | TC-NI-04 |
| NI-BC-02 | TC-NI-05 |
| NI-BC-03 | TC-NI-13 |
| NI-TC-01 | TC-NI-11 |
| NI-TC-02 | TC-NI-01 |
| NI-TC-03 | TC-NI-02 |
| NI-TC-04 | TC-NI-03 |
| NI-IN-01 | TC-NI-11 |
| NI-IN-02, NI-IN-05, NI-IN-06 | TC-NI-08 |
| NI-IN-03 | TC-NI-06 |
| NI-IN-04 | TC-NI-07 |
| NI-IN-07 | TC-NI-09 |
| NI-IN-08 | TC-NI-10 |

## 5. Negative tests

| Checker | Test |
| --- | --- |
| Invalid time-code | TC-NI-02 |
| Unknown broadcast code types | TC-NI-05 |
| Minimum interval, waiting identifier | TC-NI-06 |
| Acknowledgements in interrupt mode | TC-NI-08 |
| Indication FIFO overflow | TC-NI-12 |
| Double errors in the FIFOs | TC-NI-13 |
