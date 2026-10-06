# owr_enc

Encoding layer of OpenWire (ECSS-E-ST-50-12C Rev.1 clause 5.4): transmitter with parity, serialisation, Data-Strobe
encoding, first Null, controlled reset and data signalling rates (EN-1), sampling receiver with Null detection,
decoding, parity, ESC and disconnect errors (EN-2), and the port loopback (EN-3).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Blocks, ports, state machines, timing |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*owr_enc*"
```

| File | Content |
| --- | --- |
| `tb/owr_enc_tb.vhd`, `tb/owr_enc_th.vhd` | Testbench of the Encoding layer against the Data-Strobe far-end model |
