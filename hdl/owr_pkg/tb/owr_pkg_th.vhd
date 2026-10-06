---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of owr_pkg: owr_cc_pulse between two clocks and two Data-Strobe far-end models
-- connected to each other (self test of the verification component).
--
-- Documentation: hdl/owr_pkg/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library work;
    use work.owr_tb_ds_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_pkg_th is
    port (
        ClkA       : out   std_logic;
        ClkB       : out   std_logic;
        Rst        : in    std_logic;
        PulseIn    : in    std_logic_vector(1 downto 0);
        PulseOut   : out   std_logic_vector(1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_pkg_th is

    signal ClkA_i : std_logic := '0';
    signal ClkB_i : std_logic := '0';
    signal D01    : std_logic;
    signal S01    : std_logic;
    signal D10    : std_logic;
    signal S10    : std_logic;

begin

    ClkA_i <= not ClkA_i after 5 ns;
    ClkB_i <= not ClkB_i after 7 ns;
    ClkA   <= ClkA_i;
    ClkB   <= ClkB_i;

    i_dut : entity work.owr_cc_pulse
        generic map (
            NumPulses_g => 2
        )
        port map (
            In_Clk    => ClkA_i,
            In_Rst    => Rst,
            In_Pulse  => PulseIn,
            Out_Clk   => ClkB_i,
            Out_Rst   => Rst,
            Out_Pulse => PulseOut
        );

    -- Model 0 sends to model 1 and back
    i_bfm0 : entity work.owr_tb_ds_bfm
        generic map (
            Index_g => 0
        )
        port map (
            DOut => D01,
            SOut => S01,
            DIn  => D10,
            SIn  => S10
        );

    i_bfm1 : entity work.owr_tb_ds_bfm
        generic map (
            Index_g => 1
        )
        port map (
            DOut => D10,
            SOut => S10,
            DIn  => D01,
            SIn  => S01
        );

end architecture;
