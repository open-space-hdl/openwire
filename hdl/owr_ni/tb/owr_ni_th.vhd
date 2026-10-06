---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the Network layer: instance 1 with time-codes and distributed interrupts,
-- instance 2 without them. LinkClk 100 MHz, UserClk 62.5 MHz.
--
-- Documentation: hdl/owr_ni/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.owr_ni_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_ni_th is
    port (
        LinkClk : out   std_logic;
        UserClk : out   std_logic;
        Rst     : in    std_logic;
        NiIn1   : in    NiIn_t;
        NiOut1  : out   NiOut_t;
        NiIn2   : in    NiIn_t;
        NiOut2  : out   NiOut_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_ni_th is

    signal LinkClk_i : std_logic := '0';
    signal UserClk_i : std_logic := '0';

begin

    LinkClk_i <= not LinkClk_i after 5 ns;
    UserClk_i <= not UserClk_i after 8 ns;
    LinkClk   <= LinkClk_i;
    UserClk   <= UserClk_i;

    i_ni1 : entity work.owr_ni_tb_inst
        generic map (
            TimeCodes_g  => true,
            Interrupts_g => true,
            LogTx_g      => LogTx1_c,
            LogInd_g     => LogInd1_c
        )
        port map (
            LinkClk => LinkClk_i,
            UserClk => UserClk_i,
            Rst     => Rst,
            NiIn    => NiIn1,
            NiOut   => NiOut1
        );

    i_ni2 : entity work.owr_ni_tb_inst
        generic map (
            TimeCodes_g  => false,
            Interrupts_g => false,
            LogTx_g      => LogTx2_c,
            LogInd_g     => LogInd2_c
        )
        port map (
            LinkClk => LinkClk_i,
            UserClk => UserClk_i,
            Rst     => Rst,
            NiIn    => NiIn2,
            NiOut   => NiOut2
        );

end architecture;
