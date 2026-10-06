# owr_core

Top level of OpenWire: a SpaceWire port with a node interface (ECSS-E-ST-50-12C Rev.1). It connects the Network
layer (`owr_ni`), the Data Link layer (`owr_dl`), the Encoding layer (`owr_enc`) and the MIB (`owr_mib`), maps the
packet ports onto N-Chars (NI-1) and brings the reset into the user, link and management clock domains (MG-4).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Structure, packet mapping, clocks, ports |
| [verification_plan.md](docs/verification_plan.md) | Test cases and seams |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*owr_core*"
```

| File | Content |
| --- | --- |
| `tb/owr_core_tb.vhd` | Testbench: two cores on a line, one core against the far-end model |
| `tb/owr_core_th.vhd`, `tb/owr_core_tb_node.vhd`, `tb/owr_core_tb_pkg.vhd` | Harness: nodes with their own clocks, VVCs and indication logs, line with delay, cut and glitch |
| `tb/vunit_config.py` | Configuration `no_services` (core B without time-codes and interrupts) |
