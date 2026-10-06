# OpenWire User Guide

This guide describes how to integrate the OpenWire core `owr_core` into an FPGA design: sources, generics, clocks,
interfaces, the connection to the line drivers and receivers, the programming sequence and the performance. The
architecture is described in [architecture.md](architecture.md), the registers in the generated
[register map](../hdl/owr_mib/docs/register_map.md).

## 1. Sources

| Library | Sources | Order |
| --- | --- | --- |
| `olo` | Open Logic areas `base`, `axi`, `intf` and `ft` of the submodule `open-logic/` | `open-logic/compile_order.txt` |
| `openwire` | `hdl/<module>/src/*.vhd` of every module of `component_list.txt` | Modules in the order of `component_list.txt`; within a module packages first (`owr_pkg.vhd`, `owr_regs_pkg.vhd`) |

All sources are VHDL-2008 and contain no vendor primitive. `tools/synth_vivado.py` shows a complete source list and
the clock constraints for AMD Vivado.

## 2. Generics

| Generic | Default | Description |
| --- | --- | --- |
| `LinkClkFreq_g` | 100.0e6 | Frequency of `LinkClk` in Hz. Elaboration fails when 10 Mb/s +/- 10 % cannot be reached with an integer divider (the frequency must lie within 10 % of a multiple of 10 MHz) or when the disconnect time of 727 ns to 1 us cannot be met |
| `TxFifoDepth_g`, `RxFifoDepth_g` | 64 | Depths of the transmit and receive FIFOs in N-Chars (powers of 2). A receive FIFO of 64 or more allows seven outstanding FCTs (56 N-Chars) |
| `TimeCodes_g`, `Interrupts_g` | true | Time-code service and distributed interrupt service |
| `IntTimerWidth_g` | 16 | Width of the minimum interval and acknowledgement delay of the interrupt service, in ticks |
| `LinkDisabled_g`, `LinkStart_g`, `AutoStart_g` | false | Reset values of LinkDisabled, LinkStart and AutoStart: a port with `LinkStart_g` or `AutoStart_g` starts the link without software |
| `RunDiv_g` | 1 | Reset value of the bit period in the Run state in `LinkClk` cycles |
| `SyncStages_g` | 2 | Synchroniser stages of data and strobe |

## 3. Clocks and reset

| Clock | Function | Requirement |
| --- | --- | --- |
| `LinkClk` | Encoding and Data Link layers, Network layer functions, register file | Transmit bit period = n `LinkClk` periods (n = 1 to 255). The receiver samples data and strobe once per period: the far end's bit period, reduced by its skew and jitter, must be longer than one `LinkClk` period |
| `UserClk` | Packet and broadcast service ports | Any frequency |
| `MgmtClk` | AXI4-Lite port and `Irq` | Any frequency |

The three clocks may be the same clock. `Rst` is an asynchronous high-active reset; the core synchronises its release
in each domain. Every crossing between the domains is an Open Logic FT FIFO or synchroniser; declare the clocks
asynchronous to each other (for example `set_clock_groups -asynchronous` in Vivado).

| `LinkClk` | Initial rate | Fastest transmit rate (divider 1) | Fastest receive rate (bit period > 1.2 periods) |
| --- | --- | --- | --- |
| 50 MHz | 10 Mb/s | 50 Mb/s | about 41 Mb/s |
| 100 MHz | 10 Mb/s | 100 Mb/s | about 83 Mb/s |
| 125 MHz | 9.6 Mb/s | 125 Mb/s | about 104 Mb/s |
| 200 MHz | 10 Mb/s | 200 Mb/s | about 166 Mb/s |

The run divider must be chosen for the far end: a port must not send faster than the far end can sample.

## 4. Interfaces

### 4.1 Packet ports (`UserClk`)

`S_Pkt_*` and `M_Pkt_*` are AXI4-Stream ports with one N-Char per beat: a beat with `TLast` = '0' carries a data byte,
a beat with `TLast` = '1' is the end of packet marker and carries no data byte (`TData(0)` = '0' EOP, '1' EEP; the
receive port delivers 0x00 or 0x01). A packet of n bytes is n + 1 beats; a packet without data is a single marker
beat. A packet received with an error (link error in the middle of a packet, ECSS 5.5.8.4) ends with an EEP.

### 4.2 Broadcast services (`UserClk`)

| Port | Width | Service |
| --- | --- | --- |
| `S_Tc_*`, `M_Tc_*` | 6 | TIME-CODE.request, TIME-CODE.indication of valid time-codes |
| `S_Int_*`, `M_Int_*` | 5 | DISTRIBUTED_INTERRUPT.request and .indication |
| `S_IntAck_*`, `M_IntAck_*` | 5 | DISTRIBUTED_INTERRUPT_ACK.request and .indication |

Requests are AXI4-Stream transfers. The indication ports have a ready input (default '1'); an indication is
discarded and EVENTS.IND_OVERFLOW set when the indication FIFO (16 entries) is full. The same requests are available
through the MIB (TC_SEND, INT_SEND, INT_ACK).

The distributed interrupt service needs the timing of the network (ECSS 5.6.5.4c, d and 5.6.5.6e): INT_HOLDOFF is
the minimum interval between two interrupt codes of one identifier (longer than the propagation of an interrupt code
across the network, plus the acknowledgement time in interrupt with acknowledgement mode), INT_ACK_DELAY the minimum
delay before an acknowledgement code (longer than the propagation of the interrupt code). Both count ticks of
INT_TICK cycles (1 us after reset) and are zero after reset; set them for the network before using interrupts.

### 4.3 MIB (`MgmtClk`)

AXI4-Lite with 8-bit byte addresses and 32-bit data. Registers are written as 32-bit words. AXI4-Lite does not order
a read against an earlier write on the other channel: wait for the write response before reading a value that
depends on it. `Irq` is the OR of the error and event flags enabled in ERRORS_IRQ_EN and EVENTS_IRQ_EN.

### 4.4 Line drivers and receivers (`LinkClk`)

`Spw_DOut` and `Spw_SOut` come from flip-flops and change in the same clock edge, never together. `Spw_DIn` and
`Spw_SIn` are asynchronous; they enter a synchroniser. The target provides:

- LVDS output buffers for data and strobe (TIA-644-A, ECSS 5.3.6.2), or LVTTL inside a unit (ECSS 5.3.6.3); the
  enable `Phy_TxEn` (PORT_CTRL.DRIVER_EN) can drive the output enable of a tri-state LVDS buffer;
- LVDS input buffers with fail-safe biasing (ECSS 5.3.6.2.5) for data and strobe; `Phy_RxEn` (PORT_CTRL.RECEIVER_EN)
  can drive the enable of the input buffer;
- output flip-flops placed in the I/O blocks and matched routing of data and strobe, so that the output skew
  (DSskewOUT, ECSS 5.3.7.2g) stays small;
- timing constraints: `set_false_path` from `Spw_DIn`, `Spw_SIn` and `Rst` (they are synchronised), and the clock
  groups of section 3.

The minimum tolerated separation between edges at the receiver (MinsepIN, ECSS 5.3.7.2j) is one `LinkClk` period plus
the setup and hold window of the input flip-flops.

## 5. Fault tolerance

| Item | Protection | MIB |
| --- | --- | --- |
| FIFOs: transmit, receive, broadcast requests, broadcast indications, register requests, register responses (EDAC channels 0 to 5) | SECDED ECC on the buffer RAM: a single error is corrected, a double error is detected and contained | EVENTS.ECC_SEC, EVENTS.ECC_DED, ECC_STATUS, ECC_COUNT |
| Clock domain crossings | TMR synchronisers of the Open Logic `olo_ft_*` entities | none |
| State machines | Recovery state reached through the `when others` branch and the reset; the link state machine and the link error recovery also through the port reset | none |

A double error is never passed on as valid data: an N-Char read from the transmit FIFO is sent as an EEP and the rest
of the packet is discarded; an N-Char read from the receive FIFO is delivered as an EEP and the rest of the packet is
discarded; a broadcast request or indication is discarded; a register request or response is dropped, and the
read then ends with SLVERR after the read timeout of the AXI4-Lite slave.

The `when others` branches of the state machines are kept by synthesis only when the tool implements the state
machines safe (for example the attribute or option for safe state machines of the synthesis tool); without it, an
upset of a state register is cleared by the reset or, for the link, by PORT_CTRL.PORT_RESET. ECC_INJECT writes a
single or a double error into the next word of a FIFO for tests of the software.

## 6. Programming sequence

After reset the port is in ErrorReset or Ready according to the generics. A typical start by software:

1. Read ID (0x4F575201) and GENERICS.
2. Write LINK_SPEED.RUN_DIV with the bit period for the Run state.
3. Optionally enable interrupts: EVENTS_IRQ_EN.LINK_UP, ERRORS_IRQ_EN.
4. Write PORT_CTRL: LINK_START (or AUTO_START to wait for the far end) with DRIVER_EN and RECEIVER_EN.
5. Wait for PORT_STATUS.LINK_STATE = 5 (Run) or the LINK_UP event.
6. Exchange packets on the packet ports.

A link error (disconnect, parity, ESC or credit error) restarts the link automatically: PORT_STATUS.LAST_CAUSE, ERRORS
and the counters record it; the packet being received ends with an EEP, the rest of the packet being sent is
discarded. PORT_CTRL.PORT_RESET clears both FIFOs and restarts the link; PORT_CTRL.LINK_DISABLED stops it.

## 7. Performance

| Item | Value (simulation) |
| --- | --- |
| User data rate, packets of 1000 bytes, traffic in both directions | 97 % of the data character rate (77.7 Mb/s at 100 Mb/s) |
| Credit | Seven FCTs (56 N-Chars) with a receive FIFO of 64 |
| Latency of a received character | Two bits after its last bit (parity check of the next character) plus the FIFO crossing |

## 8. Verification and checks

```shell
python run.py -p 8                  # regression with GHDL
python run.py --questa --coverage -p 1  # regression with QuestaSim and code coverage (coverage.md)
python lint/lint.py                 # VSG
python run.py --compile
python lint/synth_check.py          # GHDL synthesis of owr_core
python tools/compliance.py --check  # ECSS traceability
python tools/regmap.py --check      # generated register map files
python tools/synth_vivado.py --part <part>  # resources and timing with AMD Vivado (licence for the part needed)
```
