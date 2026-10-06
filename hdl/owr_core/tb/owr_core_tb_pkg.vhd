---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types and constants of the core testbench: broadcast service requests of a core, observed outputs,
-- VVC instances and log indices.
--
-- Documentation: hdl/owr_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package owr_core_tb_pkg is

    -- Requests on the broadcast service ports of a core (UserClk)
    type CoreBcIn_t is record
        TcData   : std_logic_vector(5 downto 0);
        TcValid  : std_logic;
        IntData  : std_logic_vector(4 downto 0);
        IntValid : std_logic;
        AckData  : std_logic_vector(4 downto 0);
        AckValid : std_logic;
    end record;

    constant CoreBcInInit_c : CoreBcIn_t := (
        TcData   => (others => '0'),
        TcValid  => '0',
        IntData  => (others => '0'),
        IntValid => '0',
        AckData  => (others => '0'),
        AckValid => '0'
    );

    -- Observed outputs of a core
    type CoreObs_t is record
        TcReady  : std_logic;
        IntReady : std_logic;
        AckReady : std_logic;
        Irq      : std_logic;
        PhyTxEn  : std_logic;
        PhyRxEn  : std_logic;
    end record;

    -- VVC instances: AXI4-Stream packet ports and AXI4-Lite ports of cores A and B
    constant VvcATx_c : natural := 0;
    constant VvcARx_c : natural := 1;
    constant VvcBTx_c : natural := 2;
    constant VvcBRx_c : natural := 3;
    constant AxiA_c   : natural := 0;
    constant AxiB_c   : natural := 1;

    -- Far-end model instance (on the line of core A in LinkMode '1') and logs of the indications of A and B
    -- (owr_tb_farend_pkg.FarEnd_v; data = kind (7:6: 00 time-code, 01 interrupt, 10 acknowledgement) and value)
    constant Far_c  : natural := 0;
    constant IndA_c : natural := 2;
    constant IndB_c : natural := 3;

    -- Line between the cores: propagation delay
    constant LineDelay_c : time := 25 ns;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body owr_core_tb_pkg is

end package body;
