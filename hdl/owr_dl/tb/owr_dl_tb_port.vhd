---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- One port of the Data Link layer testbench: owr_enc and owr_dl with AXI4-Stream VVCs on the user
-- N-Char ports (8-bit TDATA, TLAST = end of packet marker) and counters of the status events.
--
-- Documentation: hdl/owr_dl/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.owr_pkg.all;
    use work.owr_tb_ds_pkg.all;
    use work.owr_dl_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_dl_tb_port is
    generic (
        TxVvcIdx_g : natural;
        RxVvcIdx_g : natural;
        BcLogIdx_g : natural
    );
    port (
        LinkClk  : in    std_logic;
        UserClk  : in    std_logic;
        Rst      : in    std_logic;
        Ctrl     : in    DlCtrl_t;
        Stat     : out   DlStat_t;
        Spw_DOut : out   std_logic;
        Spw_SOut : out   std_logic;
        Spw_DIn  : in    std_logic;
        Spw_SIn  : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_dl_tb_port is

    signal TxEnable  : std_logic;
    signal RxEnable  : std_logic;
    signal TxRun     : std_logic;
    signal TxKind    : CharKind_t;
    signal TxData    : std_logic_vector(7 downto 0);
    signal TxAck     : std_logic;
    signal RxValid   : std_logic;
    signal RxKind    : CharKind_t;
    signal RxData    : std_logic_vector(7 downto 0);
    signal GotNull   : std_logic;
    signal ParityErr : std_logic;
    signal EscErr    : std_logic;
    signal DiscEvt   : std_logic;
    signal TxUData   : std_logic_vector(7 downto 0);
    signal TxULast   : std_logic;
    signal TxUValid  : std_logic;
    signal TxUReady  : std_logic;
    signal RxUData   : NChar_t;
    signal RxUValid  : std_logic;
    signal RxUReady  : std_logic;
    signal RxBcData  : std_logic_vector(7 downto 0);
    signal RxBcValid : std_logic;
    signal BcDisc    : std_logic;
    signal State     : LinkState_t;
    signal Recovery  : std_logic;
    signal Cause     : ErrCause_t;
    signal TxCredit  : std_logic_vector(5 downto 0);
    signal RxCredit  : std_logic_vector(5 downto 0);
    signal TxLevel   : std_logic_vector(6 downto 0);
    signal RxLevel   : std_logic_vector(6 downto 0);
    signal Spill     : std_logic;
    signal CreditErr : std_logic;
    signal Overflow  : std_logic;
    signal TxSec     : std_logic;
    signal TxDed     : std_logic;
    signal RxSec     : std_logic;
    signal RxDed     : std_logic;
    signal TxBcReady : std_logic;

begin

    i_enc : entity work.owr_enc
        generic map (
            ClkFreq_g => 100.0e6
        )
        port map (
            Clk           => LinkClk,
            Rst           => Rst,
            TxEnable      => TxEnable,
            RxEnable      => RxEnable,
            TxRun         => TxRun,
            Cfg_RunDiv    => Ctrl.RunDiv,
            Cfg_Loopback  => '0',
            TxChar_Kind   => TxKind,
            TxChar_Data   => TxData,
            TxChar_Ack    => TxAck,
            RxChar_Valid  => RxValid,
            RxChar_Kind   => RxKind,
            RxChar_Data   => RxData,
            Rx_GotNull    => GotNull,
            Rx_ParityErr  => ParityErr,
            Rx_EscErr     => EscErr,
            Rx_Disconnect => DiscEvt,
            Spw_DOut      => Spw_DOut,
            Spw_SOut      => Spw_SOut,
            Spw_DIn       => Spw_DIn,
            Spw_SIn       => Spw_SIn
        );

    i_dl : entity work.owr_dl
        generic map (
            ClkFreq_g     => 100.0e6,
            TxFifoDepth_g => 64,
            RxFifoDepth_g => 64
        )
        port map (
            Clk              => LinkClk,
            Rst              => Rst,
            UserClk          => UserClk,
            UserRst          => Rst,
            TxUser_Data      => TxULast & TxUData,
            TxUser_Valid     => TxUValid,
            TxUser_Ready     => TxUReady,
            RxUser_Data      => RxUData,
            RxUser_Valid     => RxUValid,
            RxUser_Ready     => RxUReady,
            TxBc_Data        => Ctrl.TxBcData,
            TxBc_Valid       => Ctrl.TxBcValid,
            TxBc_Ready       => TxBcReady,
            TxBc_Discarded   => BcDisc,
            RxBc_Data        => RxBcData,
            RxBc_Valid       => RxBcValid,
            TxEnable         => TxEnable,
            RxEnable         => RxEnable,
            TxRun            => TxRun,
            TxChar_Kind      => TxKind,
            TxChar_Data      => TxData,
            TxChar_Ack       => TxAck,
            RxChar_Valid     => RxValid,
            RxChar_Kind      => RxKind,
            RxChar_Data      => RxData,
            Rx_GotNull       => GotNull,
            Rx_ParityErr     => ParityErr,
            Rx_EscErr        => EscErr,
            Rx_Disconnect    => DiscEvt,
            Cfg_PortReset    => Ctrl.PortReset,
            Cfg_LinkDisabled => Ctrl.LinkDisabled,
            Cfg_LinkStart    => Ctrl.LinkStart,
            Cfg_AutoStart    => Ctrl.AutoStart,
            Stat_State       => State,
            Stat_Recovery    => Recovery,
            Stat_Cause       => Cause,
            Stat_TxCredit    => TxCredit,
            Stat_RxCredit    => RxCredit,
            Stat_TxLevel     => TxLevel,
            Stat_RxLevel     => RxLevel,
            Stat_Spill       => Spill,
            Ev_CreditErr     => CreditErr,
            Ev_RxOverflow    => Overflow,
            Ecc_TxSec        => TxSec,
            Ecc_TxDed        => TxDed,
            Ecc_RxSec        => RxSec,
            Ecc_RxDed        => RxDed,
            Inj_TxBitFlip    => Ctrl.InjTxFlip,
            Inj_TxValid      => Ctrl.InjTxValid,
            Inj_RxBitFlip    => Ctrl.InjRxFlip,
            Inj_RxValid      => Ctrl.InjRxValid
        );

    i_tx_vvc : entity work.owr_tb_axis_master
        generic map (
            InstanceIdx_g => TxVvcIdx_g,
            DataWidth_g   => 8
        )
        port map (
            Clk       => UserClk,
            Out_Data  => TxUData,
            Out_Last  => TxULast,
            Out_Valid => TxUValid,
            Out_Ready => TxUReady
        );

    i_rx_vvc : entity work.owr_tb_axis_slave
        generic map (
            InstanceIdx_g => RxVvcIdx_g,
            DataWidth_g   => 8
        )
        port map (
            Clk      => UserClk,
            In_Data  => RxUData(7 downto 0),
            In_Last  => RxUData(NCharFlagIdx_c),
            In_Valid => RxUValid,
            In_Ready => RxUReady
        );

    -- Status and event counters
    p_stat : process (LinkClk, UserClk) is
        variable Char_v : TbChar_t;
        variable St_v   : DlStat_t := (
                                        State      => StateErrorReset_c,
                                       Recovery   => '0',
                                       Cause      => CauseNone_c,
                                       Spill      => '0',
                                       GotNull    => '0',
                                       TxBcReady  => '0',
                                       others => 0
                                   );
    begin
        if rising_edge(LinkClk) then
            if ParityErr = '1' then
                St_v.CntParity := St_v.CntParity + 1;
            end if;
            if EscErr = '1' then
                St_v.CntEsc := St_v.CntEsc + 1;
            end if;
            if DiscEvt = '1' then
                St_v.CntDisc := St_v.CntDisc + 1;
            end if;
            if CreditErr = '1' then
                St_v.CntCredit := St_v.CntCredit + 1;
            end if;
            if BcDisc = '1' then
                St_v.CntBcDisc := St_v.CntBcDisc + 1;
            end if;
            if Overflow = '1' then
                St_v.CntOverflow := St_v.CntOverflow + 1;
            end if;
            if TxSec = '1' then
                St_v.CntTxSec := St_v.CntTxSec + 1;
            end if;
            if TxDed = '1' then
                St_v.CntTxDed := St_v.CntTxDed + 1;
            end if;
            if RxBcValid = '1' then
                St_v.CntRxBc := St_v.CntRxBc + 1;
                Char_v       := TbCharInit_c;
                Char_v.Kind  := TbBc;
                Char_v.Data  := RxBcData;
                Char_v.T     := now;
                FarEnd_v.rxPush(BcLogIdx_g, Char_v);
            end if;
            if State = StateRun_c and St_v.State /= StateRun_c then
                St_v.CntRun := St_v.CntRun + 1;
            end if;
            if Recovery = '1' and St_v.Recovery = '0' then
                St_v.CntRecovery := St_v.CntRecovery + 1;
            end if;
            St_v.State     := State;
            St_v.Recovery  := Recovery;
            St_v.Cause     := Cause;
            St_v.TxCredit  := to_integer(unsigned(TxCredit));
            St_v.RxCredit  := to_integer(unsigned(RxCredit));
            St_v.TxLevel   := to_integer(unsigned(TxLevel));
            St_v.RxLevel   := to_integer(unsigned(RxLevel));
            St_v.Spill     := Spill;
            St_v.GotNull   := GotNull;
            St_v.TxBcReady := TxBcReady;
        end if;
        if rising_edge(UserClk) then
            if RxSec = '1' then
                St_v.CntRxSec := St_v.CntRxSec + 1;
            end if;
            if RxDed = '1' then
                St_v.CntRxDed := St_v.CntRxDed + 1;
            end if;
        end if;
        Stat <= St_v;
    end process;

end architecture;
