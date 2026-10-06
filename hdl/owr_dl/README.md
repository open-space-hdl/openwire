# owr_dl

Data Link layer of OpenWire (ECSS-E-ST-50-12C Rev.1 clause 5.5): transmit and receive FIFOs (DL-1, DL-2), link state
machine (DL-3), flow control manager (DL-4), transmit scheduler (DL-5), receive handler (DL-6) and link error recovery
(DL-7).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Blocks, ports, state machines |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*owr_dl*"
```

| File | Content |
| --- | --- |
| `tb/owr_dl_tb.vhd` | Testbench: link state machine, flow control, priority, broadcast codes and recovery against the far-end model; traffic, restart and EDAC between two ports |
| `tb/owr_dl_th.vhd`, `tb/owr_dl_tb_port.vhd`, `tb/owr_dl_tb_pkg.vhd` | Harness with two ports (Encoding and Data Link layer, AXI4-Stream VVCs) and the far-end model |
