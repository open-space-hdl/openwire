# OpenWire

[![TRL 3](docs/img/trl-3.svg)](https://openspacehdl.org/trl/)

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

**Technology readiness level: TRL 3** (fully verified by simulation). The core has not been tested on
hardware yet and has no flight heritage; see [what the levels mean](https://openspacehdl.org/trl/) and the next
steps in the [roadmap](docs/roadmap.md#technology-readiness).

The core is complete and verified in simulation (GHDL and QuestaSim, 84 test cases at unit, layer and core level,
statement, branch and state machine coverage closed, see [docs/coverage.md](docs/coverage.md)); the
[compliance matrix](docs/compliance.md) traces every ECSS clause in scope to its requirements and test cases. Two cores
exchange packets at 97 % of the data character rate in both directions, recover from line cuts and receive errors,
and interoperate with an independent Data-Strobe model of the far end. Synthesis results on a target device and a
hardware test are open; see [docs/roadmap.md](docs/roadmap.md).

## Documentation

The documents are also published as a website: [openspacehdl.org/openwire](https://openspacehdl.org/openwire/) (built
from this repository by `tools/docs/`).

| Document | Content |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Architecture: layers, building blocks, owned ECSS clauses, Open Logic usage, verification |
| [docs/user_guide.md](docs/user_guide.md) | Integration: sources, generics, clocks, interfaces, line drivers and receivers, programming sequence |
| [docs/conventions.md](docs/conventions.md) | Coding, verification and repository conventions |
| [docs/roadmap.md](docs/roadmap.md) | Development plan and module status |
| [docs/compliance.md](docs/compliance.md) | ECSS compliance matrix: requirements and test cases of every clause (generated) |
| [docs/coverage.md](docs/coverage.md) | Code coverage of the regression with QuestaSim |
| [hdl/owr_mib/docs/register_map.md](hdl/owr_mib/docs/register_map.md) | Register map of the MIB (generated; C header `sw/owr_regs.h`) |
| `hdl/<module>/docs/` | Specification, architecture, verification plan and verification report of each module |

## Repository structure

```text
openwire/
|-- docs/             Top-level documentation
|-- hdl/<module>/     One folder per module: src/, tb/, docs/
|-- tb/               Verification components shared by the testbenches (Data-Strobe far-end model)
|-- lint/             VSG configuration (Open Logic rules), synthesizability check
|-- tools/            Compliance matrix and register map generators, synthesis script for AMD Vivado
|   `-- docs/         Documentation website (MkDocs)
|-- sw/               C header of the register map (generated)
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
python run.py --questa --coverage -p 1  # code coverage, see docs/coverage.md
```

`run.py` compiles Open Logic into the VHDL library `olo`, the required UVVM components into their own libraries and
all OpenWire sources into the library `openwire`. `OWR_GHDL_SIM_FLAGS` passes extra flags to the GHDL simulation,
for example `--vcd=wave.vcd` for a waveform.

Checks besides the regression:

```shell
python lint/lint.py                 # VSG, no errors and no warnings
python lint/synth_check.py          # GHDL synthesis of owr_core (after python run.py --compile)
python tools/compliance.py --check  # every ECSS clause and requirement traced to a test case
python tools/regmap.py --check      # generated register map files match hdl/owr_mib/regs/owr_regs.yml
python -m mkdocs build -f tools/docs/mkdocs.yml  # documentation website, fails on broken links
```

## Licence

OpenWire is licensed under the [PSI HDL Library License, Version 1.0](License.txt), the licence of Open Logic
(LGPL 2.1 with an exception for binaries, see [LGPL2_1.txt](LGPL2_1.txt)).
