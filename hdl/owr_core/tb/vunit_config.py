# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the core testbench: core B without the broadcast services for test_no_services."""


def configure(lib):
    tb = lib.test_bench("owr_core_tb")
    tb.test("test_no_services").add_config(name="no_services", generics={"ServicesB_g": False})
