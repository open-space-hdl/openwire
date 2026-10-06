# owr_mib: Architecture and Design Description

## 1. Block diagram

```text
 MgmtClk                                          |  LinkClk
                                                  |
 AXI4-Lite --> gating --> olo_axi_lite_slave --> [request FIFO 16 x 45] --> register bus --> MG-1 owr_mib_regs
               (room)      Rb_Wr, Rb_Rd           |  tag, read, address,                    |  configuration,
                           Rb_RdData <-- tag check <-- [response FIFO 4 x 34] <-- RdData --+  commands, status,
                                                  |                                          |  flags, counters
 Irq <---------------------------- olo_ft_cc_bits <----------------------------------------- +  MG-3 olo_ft_ecc_monitor
                                                  |                                             (6 channels)
 UserClk: ECC events of receive FIFO and broadcast indication FIFO --> owr_cc_pulse --> channels 1, 3
 MgmtClk: ECC events of the response FIFO                         --> owr_cc_pulse --> channel 5
 Injection commands --> owr_cc_pulse --> UserClk (transmit FIFO, broadcast requests), MgmtClk (register requests)
```

## 2. Register bridge (MG-2, `owr_mib_bridge`)

| Item | Implementation |
| --- | --- |
| AXI4-Lite | `olo_axi_lite_slave` (one access at a time, read timeout `ReadTimeoutClks_g`); AR, AW and W valid and ready are gated by the room of the request FIFO (almost full at depth - 2) |
| Request word | Tag (2 bit), read flag, word address (6 bit), byte enables, write data (zero for reads) |
| Request FIFO | `olo_ft_fifo_async`, depth 16, read in every cycle on the `LinkClk` side: a write becomes `Rb_Wr`, a read `Rb_Rd`; a word with a double error is dropped |
| Response | The register file answers two cycles after `Rb_Rd`; the data and the tag of the last read go into the response FIFO (`olo_ft_fifo_async`, depth 4) |
| Tags | Every read increments the tag; the `MgmtClk` side passes a response only if its tag equals the tag of the read waiting and it has no double error, so a late response of a read that timed out is never taken for the next read |

AXI4-Lite does not order reads against writes; the bridge executes the accesses in the order the slave accepts them.

## 3. Register file (MG-1, `owr_mib_regs`)

The register map is in [register_map.md](register_map.md). The file is one two-process entity in `LinkClk`:

| Behaviour | Implementation |
| --- | --- |
| Write | Decoded from the word address in the cycle of `Rb_Wr`; byte enables are not used |
| Read | Address registered with `Rb_Rd`, data selected in the next cycle and registered (`Rb_RdValid` two cycles after `Rb_Rd`); the extra cycle covers the read latency of the EDAC monitor |
| Commands (W1, WO) | One-cycle pulses: port reset, TIME-CODE.request, DISTRIBUTED_INTERRUPT.request and DISTRIBUTED_INTERRUPT_ACK.request, ECC injection, ECC clear |
| Sticky flags (W1C) | `flags := (flags AND NOT written) OR events`: an event in the cycle of a clear is kept |
| Counters (RC) | Saturating; any write clears; the increment of the same cycle is lost only with the clear |
| Link up, link down, Run entries, recoveries | Edges of the link state (Run) and of the recovery state |
| Irq | Registered OR of (ERRORS AND ERRORS_IRQ_EN) and (EVENTS AND EVENTS_IRQ_EN), crossed to `MgmtClk` by `olo_ft_cc_bits` |

## 4. EDAC (MG-3)

`olo_ft_ecc_monitor` with 6 channels and 16-bit counters; `Rd_Ena` is always set, `Rd_Channel` is ECC_SELECT, a write
to ECC_COUNT is the read and clear of the selected channel, a write to ECC_STATUS the global clear.

| Channel | FIFO | Events (read side) | Injection (write side) |
| --- | --- | --- | --- |
| 0 | Transmit FIFO | LinkClk | UserClk |
| 1 | Receive FIFO | UserClk | LinkClk |
| 2 | Broadcast requests | LinkClk | UserClk |
| 3 | Broadcast indications | UserClk | LinkClk |
| 4 | Register requests | LinkClk | MgmtClk |
| 5 | Register responses | MgmtClk | LinkClk |

Events in `UserClk` and `MgmtClk` cross with `owr_cc_pulse`; events of one channel closer together than the crossing
can transfer them may be counted once. An injection flips codeword bit 3 (single) or bits 3 and 5 (double) of the next
word written.
