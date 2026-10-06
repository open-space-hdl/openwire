# owr_core: Architecture and Design Description

## 1. Block diagram

```text
                 UserClk                    LinkClk                                     MgmtClk
            +--------------------------------------------------------------------------------------+
 S_Pkt ---->| NI-1 (TLast -> marker) --> owr_dl (DL-1 .. DL-7) <--> owr_enc (EN-1 .. EN-3) |-----> Spw_DOut, Spw_SOut
 M_Pkt <----| NI-1 (marker -> TLast) <--                                                   |<----- Spw_DIn, Spw_SIn
 S_Tc, S_Int, S_IntAck ->| owr_ni (NI-2 .. NI-4) <--> TxBc / RxBc                          |
 M_Tc, M_Int, M_IntAck <-|                                                                  |
            |   owr_mib (MG-1 .. MG-3): configuration, status, events, EDAC                |<----> S_AxiLite, Irq
            |   MG-4: olo_base_reset_gen per clock domain                                   |-----> Phy_TxEn, Phy_RxEn
            +--------------------------------------------------------------------------------------+
```

## 2. Packet ports (NI-1)

| Direction | Mapping |
| --- | --- |
| Transmit | `TLast` = '0': data N-Char `'0' & TData`; `TLast` = '1': marker `'1' & "0000000" & TData(0)` (EOP or EEP) |
| Receive | `TData` = bits 7:0 of the N-Char, `TLast` = bit 8 (marker beats carry 0x00 for EOP, 0x01 for EEP) |

A packet of n data bytes is n + 1 beats. The ports are the user sides of the transmit and receive FIFOs; their
handshake follows AXI4-Stream.

## 3. Clocks and reset (MG-4)

| Domain | Blocks |
| --- | --- |
| `LinkClk` | `owr_enc`, `owr_dl` (except the user sides of the FIFOs), `owr_ni` (except the user sides of its FIFOs), `owr_mib` register file |
| `UserClk` | User sides of the transmit, receive, broadcast request and indication FIFOs |
| `MgmtClk` | AXI4-Lite slave and bridge side of the MIB, `Irq` |

`Rst` is asynchronous and high-active; one `olo_base_reset_gen` per domain synchronises its release. Port reset is the
PORT_CTRL command of the MIB.

## 4. Ports

| Signal | Width | Direction | Domain | Description |
| --- | --- | --- | --- | --- |
| `Rst` | 1 | In | async | Reset |
| `UserClk`, `LinkClk`, `MgmtClk` | 1 | In | | Clocks |
| `S_Pkt_TData`, `S_Pkt_TLast`, `S_Pkt_TValid`, `S_Pkt_TReady` | 8, 1, 1, 1 | In, In, In, Out | UserClk | Packets to send |
| `M_Pkt_TData`, `M_Pkt_TLast`, `M_Pkt_TValid`, `M_Pkt_TReady` | 8, 1, 1, 1 | Out, Out, Out, In | UserClk | Received packets |
| `S_Tc_*`, `M_Tc_*` | 6 | | UserClk | TIME-CODE.request and .indication |
| `S_Int_*`, `M_Int_*`, `S_IntAck_*`, `M_IntAck_*` | 5 | | UserClk | DISTRIBUTED_INTERRUPT and DISTRIBUTED_INTERRUPT_ACK request and indication |
| `S_AxiLite_*` | 8-bit address, 32-bit data | | MgmtClk | MIB |
| `Irq` | 1 | Out | MgmtClk | Interrupt |
| `Spw_DOut`, `Spw_SOut` | 1 | Out | LinkClk | Data and strobe to the line driver |
| `Spw_DIn`, `Spw_SIn` | 1 | In | async | Data and strobe from the line receiver |
| `Phy_TxEn`, `Phy_RxEn` | 1 | Out | LinkClk | Enable of the line driver and of the line receiver |

The generics are listed in the [specification](specification.md); the integration is described in the
[user guide](../../../docs/user_guide.md).
