# Changelog

The notable changes of OpenWire. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a
major version for an incompatible change of ports, stream formats, generics or register map, a minor version for a
feature and a patch version for a fix.

## [Unreleased]

### Changed

- Open Logic 4.8.0-ft.2 (1f4a6c3), the fault-tolerant fork based on Open Logic 4.8.0 (from 4.7.0-ft.6). The Open
  Logic VHDL sources that OpenWire uses are identical in both tags, so no port, generic or behaviour of OpenWire
  changes. Of the files of these entities only the scoped AMD Vivado constraint of `olo_base_ram_sdp` changes: it also
  finds the first read register of a LUTRAM (asynchronous FIFOs) after retiming and reports a critical warning when it
  finds none.
- Verification: the test end compares the alert counters of every level itself and ends the simulation with a
  failure, whatever the stop limits of the test.
- Documentation website: builds with Python-Markdown 3.11.3 (heading anchors hook takes the new optional argument;
  markdown pinned).

## [0.1.0] - 2026-10-18

First release. A SpaceWire port with a node interface according to ECSS-E-ST-50-12C Rev.1. Verified by simulation
(TRL 3) in GHDL and QuestaSim, on Open Logic 4.7.0-ft.6.
