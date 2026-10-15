# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the core testbench: the broadcast services of core B (test_no_services) and the reset
values of LinkDisabled, LinkStart and AutoStart of core B (test_reset_values)."""


def configure(lib):
    tb = lib.test_bench("owr_core_tb")
    services = tb.test("test_no_services")
    services.add_config(name="no_services", generics={"TimeCodesB_g": False, "InterruptsB_g": False})
    services.add_config(name="time_codes_only", generics={"TimeCodesB_g": True, "InterruptsB_g": False})
    services.add_config(name="interrupts_only", generics={"TimeCodesB_g": False, "InterruptsB_g": True})
    reset_values = tb.test("test_reset_values")
    reset_values.add_config(name="link_start", generics={"LinkStartB_g": True})
    reset_values.add_config(name="auto_start", generics={"AutoStartB_g": True})
    reset_values.add_config(name="link_disabled", generics={"LinkDisabledB_g": True})
