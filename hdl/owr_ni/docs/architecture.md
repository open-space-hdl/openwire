# owr_ni: Architecture and Design Description

## 1. Block diagram

```text
 UserClk                         |                       LinkClk
                                 |
 S_Tc, S_Ack, S_Int --> priority --> [request FIFO] --+--> NI-2 owr_ni_tc  --TxTc--+
 (AXI4-Stream)       TC > ACK > INT  (8 x 8 bit)      |                            |   NI-4 p_tx
                                 |   Mib_* requests --+--> NI-3 owr_ni_int --TxAck-+--> TC > ACK > INT --> TxBc (DL-5)
                                 |   (precedence)          (timers, register) -TxInt-+
                                 |                                                       <-- TxBc_Discarded
 M_Tc, M_Int, M_Ack <-- demux <-- [indication FIFO] <-- IndTc / IndInt / IndAck
                                 |  (16 x 8 bit)       NI-4 decode <-- RxBc (DL-6): type 00 TC, 10 INT / ACK,
                                 |                                      01, 11 or disabled service: ignored
```

Entries of both FIFOs: kind (bits 7:6: 0b00 time-code, 0b01 interrupt, 0b10 acknowledgement) and value (bits 5:0).

## 2. Broadcast code service (NI-4, `owr_ni_bc`)

| Function | Implementation |
| --- | --- |
| User requests | `olo_base_arb_prio` (3 bits, combinational) grants the time-code before the acknowledgement before the interrupt request; the granted port is ready when the request FIFO is ready |
| Request FIFO | `olo_ft_fifo_async`, depth 8, `UserClk` to `LinkClk`; read in every cycle without a MIB request; a word with a double error is read and discarded |
| MIB requests | One-cycle pulses in `LinkClk`; in their cycle the request FIFO is not read |
| Codes to send | Combinational: time-code of NI-2, else eligible acknowledgement of NI-3, else waiting interrupt of NI-3; the grant to the source is the ready of the Data Link layer (ECSS 5.6.3d) |
| Received codes | Type 0b00 to NI-2, type 0b10 with bit 5 '0' (interrupt) or '1' (acknowledgement) to NI-3; other types and codes of a disabled service: `Ev_BcIgnored` (ECSS 5.6.3f) |
| Indications | One indication per cycle at most (one received code per cycle); `olo_ft_fifo_async`, depth 16, `LinkClk` to `UserClk`; full: `Ev_IndOverflow`; the user side passes each entry to the port of its kind, a double error is read and discarded |

## 3. Time-code service (NI-2, `owr_ni_tc`)

| Register | Behaviour |
| --- | --- |
| `Reg` (time-code register) | Request: the requested value; received time-code: the received value; port reset: 0 |
| `Pending`, `PendVal` | Set by a request (a newer request replaces the value), cleared by the grant |
| Indication | Received value = `Reg` + 1 modulo 64: indication with the value; otherwise `Ev_Invalid` |

## 4. Distributed interrupt service (NI-3, `owr_ni_int`)

| Register | Set | Cleared |
| --- | --- | --- |
| `Active(i)` (interrupt register) | Interrupt code i received | Acknowledgement request i, port reset |
| `IntPend(i)` | Interrupt request i while `Holdoff(i)` = 0 and not pending (otherwise `Ev_IntReqDiscarded`) | Grant |
| `AckPend(i)` | Acknowledgement request i in interrupt with acknowledgement mode (in interrupt mode `Ev_AckReqDiscarded`) | Grant |
| `Holdoff(i)` | Interrupt code i passed to the Data Link layer and not discarded: `Cfg_Holdoff` + 1 | Decremented every tick |
| `Delay(i)` | Interrupt code i received: `Cfg_AckDelay` + 1 | Decremented every tick |

A load of n + 1 ticks guarantees at least n tick periods, because the first tick can come in the cycle after the
load; a configuration of 0 disables the timer. The tick is a down-counter of `Cfg_Tick` cycles. Waiting interrupt
codes and eligible acknowledgements (`AckPend(i)` and `Delay(i)` = 0) are granted by `olo_base_arb_prio`
(combinational, highest identifier first). A received acknowledgement code is indicated in interrupt with
acknowledgement mode and discarded in interrupt mode (`Ev_AckIgnored`).

## 5. Disabled services (`owr_ni`)

With `TimeCodes_g` = false or `Interrupts_g` = false the service entity is not instantiated: its codes are never sent,
its received codes are ignored by NI-4 and its requests are read from the FIFO and dropped (interrupt and
acknowledgement requests are reported as discarded).

## 6. Ports of `owr_ni`

| Signal | Domain | Description |
| --- | --- | --- |
| `S_Tc_*` (6 bit), `S_Int_*`, `S_Ack_*` (5 bit) | UserClk | TIME-CODE.request, DISTRIBUTED_INTERRUPT.request, DISTRIBUTED_INTERRUPT_ACK.request |
| `M_Tc_*`, `M_Int_*`, `M_Ack_*` | UserClk | The indications |
| `Mib_*Valid`, `Mib_TcValue`, `Mib_IntIid`, `Mib_AckIid` | LinkClk | Requests of the MIB |
| `Cfg_PortReset`, `Cfg_AckMode`, `Cfg_IntTick`, `Cfg_IntHoldoff`, `Cfg_AckDelay` | LinkClk | Configuration |
| `TxBc_*`, `TxBc_Discarded`, `RxBc_*` | LinkClk | Data Link layer |
| `Stat_TimeCode`, `Stat_IntActive`, `Ev_*` | LinkClk | Status and events for the MIB |
| `Ecc_Req*`, `Inj_Ind*` | LinkClk | ECC events of the request FIFO, injection into the indication FIFO |
| `Ecc_Ind*`, `Inj_Req*` | UserClk | ECC events of the indication FIFO, injection into the request FIFO |
