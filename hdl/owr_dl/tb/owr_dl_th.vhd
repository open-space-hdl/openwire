---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the Data Link layer: port A (owr_enc and owr_dl) on a line to either the
-- Data-Strobe far-end model (LinkMode = '0') or port B (LinkMode = '1'). Cut = '1' stops both
-- directions of the line (disconnect). LinkClk 100 MHz, UserClk 83.3 MHz.
--
-- Documentation: hdl/owr_dl/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library uvvm_vvc_framework;

library work;
    use work.owr_dl_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_dl_th is
    port (
        LinkClk  : out   std_logic;
        UserClk  : out   std_logic;
        Rst      : in    std_logic;
        CtrlA    : in    DlCtrl_t;
        CtrlB    : in    DlCtrl_t;
        StatA    : out   DlStat_t;
        StatB    : out   DlStat_t;
        LinkMode : in    std_logic;
        Cut      : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_dl_th is

    signal LinkClk_i : std_logic := '0';
    signal UserClk_i : std_logic := '0';
    signal DOutA     : std_logic;
    signal SOutA     : std_logic;
    signal DInA      : std_logic;
    signal SInA      : std_logic;
    signal DOutB     : std_logic;
    signal SOutB     : std_logic;
    signal DInB      : std_logic;
    signal SInB      : std_logic;
    signal DOutFar   : std_logic;
    signal SOutFar   : std_logic;
    signal LineD     : std_logic;
    signal LineS     : std_logic;

begin

    i_uvvm : entity uvvm_vvc_framework.ti_uvvm_engine;

    LinkClk_i <= not LinkClk_i after 5 ns;
    UserClk_i <= not UserClk_i after 6 ns;
    LinkClk   <= LinkClk_i;
    UserClk   <= UserClk_i;

    i_a : entity work.owr_dl_tb_port
        generic map (
            TxVvcIdx_g => VvcATx_c,
            RxVvcIdx_g => VvcARx_c,
            BcLogIdx_g => BcLogA_c
        )
        port map (
            LinkClk  => LinkClk_i,
            UserClk  => UserClk_i,
            Rst      => Rst,
            Ctrl     => CtrlA,
            Stat     => StatA,
            Spw_DOut => DOutA,
            Spw_SOut => SOutA,
            Spw_DIn  => DInA,
            Spw_SIn  => SInA
        );

    i_b : entity work.owr_dl_tb_port
        generic map (
            TxVvcIdx_g => VvcBTx_c,
            RxVvcIdx_g => VvcBRx_c,
            BcLogIdx_g => BcLogB_c
        )
        port map (
            LinkClk  => LinkClk_i,
            UserClk  => UserClk_i,
            Rst      => Rst,
            Ctrl     => CtrlB,
            Stat     => StatB,
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

    -- Line to port A: far-end model or port B; a cut line keeps its last levels
    LineD <= DOutFar when LinkMode = '0' else DOutB;
    LineS <= SOutFar when LinkMode = '0' else SOutB;

    p_line : process (all) is
    begin
        if Cut = '0' then
            DInA <= LineD;
            SInA <= LineS;
            DInB <= DOutA;
            SInB <= SOutA;
        end if;
    end process;

end architecture;
