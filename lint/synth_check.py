# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Synthesis check of OpenWire with GHDL: elaborates and synthesises owr_core at the bounds of every generic range
(TC-CORE-16), and checks that every configuration outside the ranges stops the elaboration with its message.

Usage: python lint/synth_check.py [name ...]
Uses the libraries compiled by the regression runner (run `python run.py --compile` first). Names select
configurations; without names all run. Exit code 0 when every configuration synthesises without error and without
inferred latch, and every configuration outside the ranges stops with its expected message.
GHDL cannot override a real generic, so the check synthesises a wrapper generated from the entity of owr_core with
the generic LinkClkKHz_g (LinkClkFreq_g = 1000 * LinkClkKHz_g) in place of LinkClkFreq_g.
This is a technology-independent check of synthesizability; resources and timing need the FPGA tools.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBS = ROOT / "vunit_out" / "ghdl" / "libraries"
CORE = ROOT / "hdl" / "owr_core" / "src" / "owr_core.vhd"

# Configurations that must synthesise: the defaults, every combination of the broadcast services and the bounds of
# every numeric range (the valid LinkClkFreq_g are 18 to 22, 27 to 33, 36 to 44 and 45 to 2554 MHz)
CONFIGS = [
    ("default", {}),
    ("no_services", {"TimeCodes_g": "false", "Interrupts_g": "false"}),
    ("time_codes_only", {"TimeCodes_g": "true", "Interrupts_g": "false"}),
    ("interrupts_only", {"TimeCodes_g": "false", "Interrupts_g": "true"}),
    ("fifos_min", {"TxFifoDepth_g": "2", "RxFifoDepth_g": "16"}),
    ("fifos_max", {"TxFifoDepth_g": "32768", "RxFifoDepth_g": "32768"}),
    ("int_timer_1", {"IntTimerWidth_g": "1"}),
    ("int_timer_30", {"IntTimerWidth_g": "30"}),
    ("run_div_255", {"RunDiv_g": "255"}),
    ("sync_stages_4", {"SyncStages_g": "4"}),
    ("reset_values", {"LinkDisabled_g": "true", "LinkStart_g": "true", "AutoStart_g": "true"}),
] + [(f"link_clk_{mhz}", {"LinkClkKHz_g": str(mhz * 1000)}) for mhz in (18, 22, 27, 33, 36, 44, 45, 2554)]

# Configurations outside the ranges and the message their elaboration stops with
NEGATIVE = [
    ("rx_fifo_8", {"RxFifoDepth_g": "8"}, "RxFifoDepth_g must be 16 to 32768"),
    ("rx_fifo_65536", {"RxFifoDepth_g": "65536"}, "RxFifoDepth_g must be 16 to 32768"),
    ("tx_fifo_1", {"TxFifoDepth_g": "1"}, "value out of range"),  # stopped by the Open Logic FIFO
    ("tx_fifo_65536", {"TxFifoDepth_g": "65536"}, "TxFifoDepth_g must be 2 to 32768"),
    ("link_clk_11", {"LinkClkKHz_g": "11000"}, "below 13.2 MHz"),
    ("link_clk_25", {"LinkClkKHz_g": "25000"}, "does not allow 10 Mb/s"),
    ("link_clk_2555", {"LinkClkKHz_g": "2555000"}, "initial divider above 255"),
]


def wrapper_source():
    """Entity owr_core_synth with the generics and ports of owr_core, LinkClkFreq_g replaced by LinkClkKHz_g."""
    text = CORE.read_text(encoding="utf-8")
    entity = re.search(r"^entity owr_core is\n(.*?)^end entity;", text, re.S | re.M).group(1)
    generic_part, port_part = entity.split("    port (", 1)
    generics = re.findall(r"^\s+(\w+_g)\s*:", generic_part, re.M)
    ports = re.findall(r"^\s+(\w+)\s*:\s*(?:in|out)\b", port_part, re.M)
    entity = re.sub(r"^(\s+)LinkClkFreq_g(\s*):\s*real\s*:=\s*[0-9.e]+;",
                    r"\1LinkClkKHz_g\2: positive := 100000;", entity, flags=re.M)
    maps = ["LinkClkFreq_g => real(LinkClkKHz_g) * 1.0e3" if g == "LinkClkFreq_g" else f"{g} => {g}"
            for g in generics]
    return "\n".join([
        "library ieee;",
        "    use ieee.std_logic_1164.all;",
        "library openwire;",
        "entity owr_core_synth is",
        entity.rstrip(),
        "end entity;",
        "architecture rtl of owr_core_synth is",
        "begin",
        "    i_core : entity openwire.owr_core",
        "        generic map (" + ", ".join(maps) + ")",
        "        port map (" + ", ".join(f"{p} => {p}" for p in ports) + ");",
        "end architecture;",
        "",
    ])


def ghdl(args, out_file=None):
    base = ["--std=08", "-frelaxed", f"-P{LIBS / 'olo'}", f"-P{LIBS / 'openwire'}"]
    if out_file is None:
        res = subprocess.run(["ghdl", args[0]] + base + args[1:], capture_output=True, text=True)
    else:
        with open(out_file, "w") as netlist:
            res = subprocess.run(["ghdl", args[0]] + base + args[1:], stdout=netlist, stderr=subprocess.PIPE,
                                 text=True)
    return res.returncode, res.stderr


def run_synth(generics, work, out_file):
    args = ["--synth", "--work=synth", f"--workdir={work}"]
    args += [f"-g{name}={value}" for name, value in generics.items()]
    return ghdl(args + ["owr_core_synth"], out_file)


def synth(name, generics, work):
    code, log = run_synth(generics, work, work / f"{name}.vhd")
    # Inferred latches are reported as "latch" warnings
    latches = [line for line in log.splitlines() if re.search(r"\blatch\b", line, re.IGNORECASE)]
    errors = [line for line in log.splitlines() if "error" in line.lower() or "exception" in line.lower()]
    ok = code == 0 and not latches and not errors
    print(f"{name}: {'OK' if ok else 'FAILED'}")
    for line in (errors + latches)[:20]:
        print("  " + line)
    return ok


def outside(name, generics, message, work):
    code, log = run_synth(generics, work, work / f"{name}.vhd")
    ok = code != 0 and message in log
    print(f"{name}: {'stopped as expected' if ok else 'FAILED'}")
    if not ok:
        for line in log.splitlines()[:20]:
            print("  " + line)
    return ok


def main():
    if not LIBS.exists():
        raise SystemExit("compiled libraries not found, run: python run.py --compile")
    names = set(sys.argv[1:])
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        source = work / "owr_core_synth.vhd"
        source.write_text(wrapper_source(), encoding="utf-8")
        code, log = ghdl(["-a", "--work=synth", f"--workdir={work}", str(source)])
        if code != 0:
            raise SystemExit("wrapper does not analyse:\n" + log)
        results = [synth(n, g, work) for n, g in CONFIGS if not names or n in names]
        results += [outside(n, g, m, work) for n, g, m in NEGATIVE if not names or n in names]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
