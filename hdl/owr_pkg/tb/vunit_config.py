# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the pulse crossing testbench: faster input clock, faster output clock, nearly equal clocks
(LinkClk and UserClk of node A of the core testbench)."""


def configure(lib):
    tb = lib.test_bench("owr_cc_pulse_tb")
    for name, in_ps, out_ps in (("in_fast", 4000, 10000), ("out_fast", 10000, 4000), ("near", 10000, 12000)):
        tb.add_config(name=name, generics={"InPeriodPs_g": in_ps, "OutPeriodPs_g": out_ps})
