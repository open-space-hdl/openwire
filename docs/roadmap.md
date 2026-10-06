# OpenWire Roadmap

The development follows the plan of the [architecture](architecture.md) (section 11). This page tracks the state of
every module; a module is done when its verification report is written and its regression is green.

## Modules

| Module | Blocks (architecture section 7) | Status |
| --- | --- | --- |
| `owr_pkg` | Common constants and types, register package, `owr_cc_pulse` | Done |
| `tb` (shared) | Verification helpers, Data-Strobe far-end model, AXI4-Stream and AXI4-Lite VVC wrappers | Done |
| `owr_enc` | EN-1 transmitter, EN-2 receiver, EN-3 port loopback | Done |
| `owr_dl` | DL-1 to DL-7 (Data Link layer) | Done |
| `owr_ni` | NI-2 to NI-4 (Network layer of a node; NI-1 in `owr_core`) | Done |
| `owr_mib` | MG-1 to MG-3 (register file, register bridge, EDAC monitor) | Done |
| `owr_core` | Core top level, NI-1, MG-4 | Done |

## Open items

| Item | State |
| --- | --- |
| Synthesis on a target device: resources and timing closure of `LinkClk` | Open; `tools/synth_vivado.py` runs the out-of-context flow with AMD Vivado |
| Hardware test against SpaceWire equipment (LVDS I/O buffers of the target, cable) | Open |
| Code coverage with QuestaSim | Open |
