# owr_pkg

Common package of OpenWire (character kinds, N-Char format, link states, broadcast code fields, timer conversions,
parity), the generated register package and the pulse crossing `owr_cc_pulse`. The module also verifies the shared
Data-Strobe far-end model of `tb/`.

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Contents, character encoding, far-end model |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*owr_pkg*"
```

| File | Content |
| --- | --- |
| `tb/owr_pkg_tb.vhd`, `tb/owr_pkg_th.vhd` | Testbench of the package functions, of `owr_cc_pulse` and self test of the far-end model |
