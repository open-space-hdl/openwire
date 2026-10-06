# OpenWire Roadmap

The development follows the plan of the [architecture](architecture.md) (section 11). This page tracks the state of
every module; a module is done when its verification report is written and its regression is green.

## Modules

| Module | Blocks (architecture section 7) | Status |
| --- | --- | --- |
| `owr_pkg` | Common constants and types, `owr_cc_pulse` | Done |
| `tb` (shared) | Verification helpers, Data-Strobe far-end model | Done (far-end model); link model with the core |
| `owr_enc` | EN-1 transmitter, EN-2 receiver, EN-3 port loopback | Done |
| `owr_dl` | DL-1 to DL-7 (Data Link layer) | Done |
| `owr_ni` | NI-1 to NI-4 (Network layer of a node) | Open |
| `owr_mib` | MG-1 to MG-3 (register file, register bridge, EDAC monitor) | Open |
| `owr_core` | Core top level, MG-4 | Open |
