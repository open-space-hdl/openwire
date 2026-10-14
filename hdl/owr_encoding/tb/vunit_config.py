# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the Encoding layer testbench: the receive tests with 2, 3 and 4 synchroniser stages."""

RX_TESTS = ("test_null_detection", "test_rx_characters", "test_rx_parity", "test_rx_esc_error", "test_rx_disconnect",
            "test_rx_simultaneous", "test_rx_rates", "test_loopback")


def configure(lib):
    tb = lib.test_bench("owr_encoding_tb")
    for name in RX_TESTS:
        test = tb.test(name)
        for stages in (2, 3, 4):
            test.add_config(name=f"sync_{stages}", generics={"SyncStages_g": stages})
