# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the MIB testbench: the register bridge with a fast, a slow and a very fast management
clock."""


def configure(lib):
    tb = lib.test_bench("owr_mib_tb")
    test = tb.test("test_read_after_write")
    # MgmtClk 166.7 MHz (faster than LinkClk), 25 MHz (slower than LinkClk) and 500 MHz (back-to-back writes fill
    # the request FIFO)
    test.add_config(name="mgmt_fast", generics={"MgmtHalfPs_g": 3000})
    test.add_config(name="mgmt_slow", generics={"MgmtHalfPs_g": 20000})
    test.add_config(name="mgmt_very_fast", generics={"MgmtHalfPs_g": 1000})
