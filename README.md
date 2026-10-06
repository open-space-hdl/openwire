# OpenWire

OpenWire is an open SpaceWire implementation that is based on the Open Logic VHDL Library.

It implements a SpaceWire port with a node interface according to
[ECSS-E-ST-50-12C Rev.1](https://ecss.nl/standard/ecss-e-st-50-12c-rev-1-spacewire-links-nodes-routers-and-networks-15-may-2019/)
(15 May 2019): Encoding layer (Data-Strobe encoding and decoding, parity, Null detection, disconnect, data signalling
rates), Data Link layer (flow control, sending priority, link state machine, link error recovery), the Network layer
of a node (packet service, time-codes, distributed interrupts) and the Management Information Base with an AXI4-Lite
register interface. The port contains no vendor code: the receiver samples data and strobe with the port clock, and
every FIFO and clock domain crossing uses the fault-tolerant entities of
[Open Logic](https://github.com/open-logic/open-logic) (SECDED ECC, TMR synchronisers).

## Status

See [docs/roadmap.md](docs/roadmap.md) for the state of every module.

## Documentation

| Document | Content |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Architecture: layers, building blocks, owned ECSS clauses, Open Logic usage, verification |
| [docs/conventions.md](docs/conventions.md) | Coding, verification and repository conventions |
| [docs/roadmap.md](docs/roadmap.md) | Development plan and module status |
| `hdl/<module>/docs/` | Specification, architecture, verification plan and verification report of each module |

## Repository structure

```text
openwire/
|-- docs/             Top-level documentation
|-- hdl/<module>/     One folder per module: src/, tb/, docs/
|-- tb/               Verification components shared by the testbenches (Data-Strobe far-end model)
|-- lint/             VSG configuration (Open Logic rules)
|-- open-logic/       Git submodule: Open Logic (fault-tolerant entities branch)
|-- uvvm/             Git submodule: UVVM verification framework
|-- component_list.txt  Modules in dependency order
`-- run.py            VUnit regression runner
```

## Running the tests

Prerequisites: Python 3, [GHDL](https://github.com/ghdl/ghdl) on the `PATH` and the Python packages of
`requirements.txt`.

```shell
git submodule update --init
python -m pip install -r requirements.txt
python run.py -p 8              # full regression with GHDL, 8 parallel simulations
python run.py "*owr_enc*"       # one module
python run.py --questa <test>   # QuestaSim
```

`run.py` compiles Open Logic into the VHDL library `olo`, the required UVVM components into their own libraries and
all OpenWire sources into the library `openwire`. `OWR_GHDL_SIM_FLAGS` passes extra flags to the GHDL simulation,
for example `--vcd=wave.vcd` for a waveform.

Checks besides the regression:

```shell
python lint/lint.py                 # VSG, no errors and no warnings
```

## Licence

OpenWire is licensed under the [PSI HDL Library License, Version 1.0](License.txt), the licence of Open Logic
(LGPL 2.1 with an exception for binaries, see [LGPL2_1.txt](LGPL2_1.txt)).
