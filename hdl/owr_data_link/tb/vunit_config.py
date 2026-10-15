# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the Data Link layer testbench: the minimum FIFO depths (transmit 2, receive 16) for
test_small_fifos."""


def configure(lib):
    tb = lib.test_bench("owr_data_link_tb")
    tb.test("test_small_fifos").add_config(name="fifos_min", generics={"TxFifoDepth_g": 2, "RxFifoDepth_g": 16})
