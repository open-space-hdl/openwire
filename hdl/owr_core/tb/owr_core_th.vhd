---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the core: node A (LinkClk 100 MHz, UserClk 83.3 MHz, MgmtClk 50 MHz) and node B
-- (125 MHz, 62.5 MHz, 100 MHz) on a line with a propagation delay, or node A against the Data-Strobe
-- far-end model (LinkMode = '1'). Cut stops both directions, Glitch inverts the data line from A to
-- B for 12 ns.
--
-- Documentation: hdl/owr_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_vvc_framework;

library work;
    use work.owr_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_core_th is
    generic (
        ServicesB_g : boolean := true
    );
    port (
        Rst      : in    std_logic;
        BcInA    : in    CoreBcIn_t;
        BcInB    : in    CoreBcIn_t;
        ObsA     : out   CoreObs_t;
        ObsB     : out   CoreObs_t;
        UserClkA : out   std_logic;
        UserClkB : out   std_logic;
        LinkClkA : out   std_logic;
        LinkMode : in    std_logic;
        Cut      : in    std_logic;
        Glitch   : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_core_th is

    signal DOutA   : std_logic;
    signal SOutA   : std_logic;
    signal DInA    : std_logic;
    signal SInA    : std_logic;
    signal DOutB   : std_logic;
    signal SOutB   : std_logic;
    signal DInB    : std_logic;
    signal SInB    : std_logic;
    signal DOutFar : std_logic;
    signal SOutFar : std_logic;
    signal DelD_AB : std_logic;
    signal DelS_AB : std_logic;
    signal DelD_BA : std_logic;
    signal DelS_BA : std_logic;
    signal GlD     : std_logic := '0';

begin

    i_uvvm : entity uvvm_vvc_framework.ti_uvvm_engine;

    i_a : entity work.owr_core_tb_node
        generic map (
            LinkHalf_g => 5 ns,
            UserHalf_g => 6 ns,
            MgmtHalf_g => 10 ns,
            LinkFreq_g => 100.0e6,
            Services_g => true,
            TxVvc_g    => VvcATx_c,
            RxVvc_g    => VvcARx_c,
            AxiVvc_g   => AxiA_c,
            IndLog_g   => IndA_c
        )
        port map (
            Rst      => Rst,
            BcIn     => BcInA,
            Obs      => ObsA,
            UserClk  => UserClkA,
            LinkClk  => LinkClkA,
            Spw_DOut => DOutA,
            Spw_SOut => SOutA,
            Spw_DIn  => DInA,
            Spw_SIn  => SInA
        );

    i_b : entity work.owr_core_tb_node
        generic map (
            LinkHalf_g => 4 ns,
            UserHalf_g => 8 ns,
            MgmtHalf_g => 5 ns,
            LinkFreq_g => 125.0e6,
            Services_g => ServicesB_g,
            TxVvc_g    => VvcBTx_c,
            RxVvc_g    => VvcBRx_c,
            AxiVvc_g   => AxiB_c,
            IndLog_g   => IndB_c
        )
        port map (
            Rst      => Rst,
            BcIn     => BcInB,
            Obs      => ObsB,
            UserClk  => UserClkB,
            LinkClk  => open,
            Spw_DOut => DOutB,
            Spw_SOut => SOutB,
            Spw_DIn  => DInB,
            Spw_SIn  => SInB
        );

    i_far : entity work.owr_tb_ds_bfm
        generic map (
            Index_g => Far_c
        )
        port map (
            DOut => DOutFar,
            SOut => SOutFar,
            DIn  => DOutA,
            SIn  => SOutA
        );

    -- Line with propagation delay; a cut line keeps its last levels; a glitch inverts the data from A to B
    DelD_AB <= transport DOutA after LineDelay_c;
    DelS_AB <= transport SOutA after LineDelay_c;
    DelD_BA <= transport DOutB after LineDelay_c;
    DelS_BA <= transport SOutB after LineDelay_c;

    p_glitch : process is
    begin
        wait until rising_edge(Glitch);
        GlD <= '1';
        wait for 12 ns;
        GlD <= '0';
    end process;

    p_line : process (all) is
    begin
        if Cut = '0' then
            DInB <= DelD_AB xor GlD;
            SInB <= DelS_AB;
            if LinkMode = '0' then
                DInA <= DelD_BA;
                SInA <= DelS_BA;
            else
                DInA <= DOutFar;
                SInA <= SOutFar;
            end if;
        end if;
    end process;

end architecture;
