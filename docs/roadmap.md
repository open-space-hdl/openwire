# OpenWire Roadmap

The development follows the plan of the [architecture](architecture.md) (section 11). This page tracks the state of
every module; a module is done when its verification report is written and its regression is green.

## Technology readiness

The core is at **TRL 3**: fully verified by simulation, not yet tested on hardware, no flight heritage. The
[TRL page](https://openspacehdl.org/trl/) explains what the levels mean for an IP core.

| Next level | What is needed | State |
| --- | --- | --- |
| TRL 4 | Synthesis and timing closure on a target FPGA; hardware test in the laboratory, two ports in loopback and against independent SpaceWire equipment at all data signalling rates; hardware test plan and test report | Open (see the open items) |
| TRL 5 | Single-event effects test (beam test) on a radiation-tolerant FPGA with the core in operation that confirms the single-event mitigation and quantifies the error rates; operation over the temperature range | Open |

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
| Code coverage with QuestaSim | Done: [coverage.md](coverage.md) |
