# owr_core: Architecture and Design Description

## 1. Block diagram

![Block diagram of owr_core: packet port (NI-1), owr_data_link, owr_encoding, owr_network, owr_mib and the reset
generators (MG-4)](img/owr_core_arch.drawio.svg)

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
| `LinkClk` | `owr_encoding`, `owr_data_link` (except the user sides of the FIFOs), `owr_network` (except the user sides of its FIFOs), `owr_mib` register file |
| `UserClk` | User sides of the transmit, receive, broadcast request and indication FIFOs |
| `MgmtClk` | AXI4-Lite slave and bridge side of the MIB, `Irq` |

`Rst` is asynchronous and high-active; one `olo_ft_reset_gen` per domain (three reset synchroniser chains and a
majority voter) synchronises its release. Port reset is the PORT_CTRL command of the MIB.

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
