# owr_mib

Management Information Base of OpenWire (ECSS-E-ST-50-12C Rev.1 clauses 5.7 and 6.5): register file in the link clock
(MG-1), register bridge from the AXI4-Lite port in the management clock through FT FIFOs (MG-2), and the EDAC monitor
of all FIFOs with error injection (MG-3). The register map is generated from [regs/owr_regs.yml](regs/owr_regs.yml).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Blocks, bridge, register file, EDAC |
| [register_map.md](docs/register_map.md) | Registers and fields (generated) |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*owr_mib*"
python tools/regmap.py --check
```

| File | Content |
| --- | --- |
| `tb/owr_mib_tb.vhd`, `tb/owr_mib_th.vhd`, `tb/owr_mib_tb_pkg.vhd` | Testbench with the AXI4-Lite VVC and observers of all outputs |
| `tb/vunit_config.py` | Configurations of the register bridge test with a fast and a slow management clock |
