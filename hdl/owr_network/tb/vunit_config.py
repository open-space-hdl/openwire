# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the Network layer testbench: the services of instance 2 for test_disabled_services."""


def configure(lib):
    tb = lib.test_bench("owr_network_tb")
    test = tb.test("test_disabled_services")
    test.add_config(name="no_services", generics={"TimeCodes2_g": False, "Interrupts2_g": False})
    test.add_config(name="time_codes_only", generics={"TimeCodes2_g": True, "Interrupts2_g": False})
    test.add_config(name="interrupts_only", generics={"TimeCodes2_g": False, "Interrupts2_g": True})
