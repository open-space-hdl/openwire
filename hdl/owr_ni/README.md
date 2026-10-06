# owr_ni

Network layer of OpenWire for a node with one end-point (ECSS-E-ST-50-12C Rev.1 clause 5.6): time-code service with
the time-code register (NI-2), distributed interrupt service in interrupt mode and interrupt with acknowledgement mode
(NI-3) and the broadcast code service with the request and indication FIFOs to the user clock (NI-4). The packet
service (NI-1) is the N-Char stream of the Data Link layer, connected in `owr_core`.

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Blocks, registers, ports |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*owr_ni*"
```

| File | Content |
| --- | --- |
| `tb/owr_ni_tb.vhd` | Testbench of the services, priorities, disabled services and FIFOs |
| `tb/owr_ni_th.vhd`, `tb/owr_ni_tb_inst.vhd`, `tb/owr_ni_tb_pkg.vhd` | Harness with two instances, model of the broadcast slot, logs and counters |
