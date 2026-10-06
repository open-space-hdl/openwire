---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- One owr_ni of the Network layer testbench with a model of the broadcast slot of the Data Link
-- layer, logs of the sent codes and of the indications, and event counters.
--
-- Documentation: hdl/owr_ni/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.owr_pkg.all;
    use work.owr_tb_ds_pkg.all;
    use work.owr_ni_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_ni_tb_inst is
    generic (
        TimeCodes_g  : boolean;
        Interrupts_g : boolean;
        LogTx_g      : natural;
        LogInd_g     : natural
    );
    port (
        LinkClk : in    std_logic;
        UserClk : in    std_logic;
        Rst     : in    std_logic;
        NiIn    : in    NiIn_t;
        NiOut   : out   NiOut_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_ni_tb_inst is

    signal MTcData   : std_logic_vector(5 downto 0);
    signal MTcValid  : std_logic;
    signal MIntData  : std_logic_vector(4 downto 0);
    signal MIntValid : std_logic;
    signal MAckData  : std_logic_vector(4 downto 0);
    signal MAckValid : std_logic;
    signal TxData    : std_logic_vector(7 downto 0);
    signal TxValid   : std_logic;
    signal TxDisc    : std_logic;
    signal TimeCode  : std_logic_vector(5 downto 0);
    signal IntActive : std_logic_vector(31 downto 0);
    signal EvTcValid : std_logic;
    signal EvTcInv   : std_logic;
    signal EvIntRx   : std_logic;
    signal EvAckRx   : std_logic;
    signal EvAckIid  : std_logic_vector(4 downto 0);
    signal EvIntDisc : std_logic;
    signal EvAckDisc : std_logic;
    signal EvIgnored : std_logic;
    signal EvIndOvf  : std_logic;
    signal ReqSec    : std_logic;
    signal ReqDed    : std_logic;
    signal IndSec    : std_logic;
    signal IndDed    : std_logic;
    signal TcReady   : std_logic;
    signal IntReady  : std_logic;
    signal AckReady  : std_logic;

begin

    i_dut : entity work.owr_ni
        generic map (
            TimeCodes_g     => TimeCodes_g,
            Interrupts_g    => Interrupts_g,
            IntTimerWidth_g => 16
        )
        port map (
            Clk                => LinkClk,
            Rst                => Rst,
            UserClk            => UserClk,
            UserRst            => Rst,
            S_Tc_TData         => NiIn.TcData,
            S_Tc_TValid        => NiIn.TcValid,
            S_Tc_TReady        => TcReady,
            S_Int_TData        => NiIn.IntData,
            S_Int_TValid       => NiIn.IntValid,
            S_Int_TReady       => IntReady,
            S_Ack_TData        => NiIn.AckData,
            S_Ack_TValid       => NiIn.AckValid,
            S_Ack_TReady       => AckReady,
            M_Tc_TData         => MTcData,
            M_Tc_TValid        => MTcValid,
            M_Tc_TReady        => NiIn.IndReady,
            M_Int_TData        => MIntData,
            M_Int_TValid       => MIntValid,
            M_Int_TReady       => NiIn.IndReady,
            M_Ack_TData        => MAckData,
            M_Ack_TValid       => MAckValid,
            M_Ack_TReady       => NiIn.IndReady,
            Mib_TcValid        => NiIn.MibTcValid,
            Mib_TcValue        => NiIn.MibTcValue,
            Mib_IntValid       => NiIn.MibIntValid,
            Mib_IntIid         => NiIn.MibIntIid,
            Mib_AckValid       => NiIn.MibAckValid,
            Mib_AckIid         => NiIn.MibAckIid,
            Cfg_PortReset      => NiIn.PortReset,
            Cfg_AckMode        => NiIn.AckMode,
            Cfg_IntTick        => NiIn.IntTick,
            Cfg_IntHoldoff     => NiIn.IntHoldoff,
            Cfg_AckDelay       => NiIn.AckDelay,
            TxBc_Data          => TxData,
            TxBc_Valid         => TxValid,
            TxBc_Ready         => NiIn.DlReady,
            TxBc_Discarded     => TxDisc,
            RxBc_Data          => NiIn.RxData,
            RxBc_Valid         => NiIn.RxValid,
            Stat_TimeCode      => TimeCode,
            Stat_IntActive     => IntActive,
            Ev_TcValid         => EvTcValid,
            Ev_TcInvalid       => EvTcInv,
            Ev_IntRx           => EvIntRx,
            Ev_AckRx           => EvAckRx,
            Ev_AckRxIid        => EvAckIid,
            Ev_IntReqDiscarded => EvIntDisc,
            Ev_AckReqDiscarded => EvAckDisc,
            Ev_BcIgnored       => EvIgnored,
            Ev_IndOverflow     => EvIndOvf,
            Ecc_ReqSec         => ReqSec,
            Ecc_ReqDed         => ReqDed,
            Ecc_IndSec         => IndSec,
            Ecc_IndDed         => IndDed,
            Inj_ReqBitFlip     => NiIn.InjReqFlip,
            Inj_ReqValid       => NiIn.InjReqValid,
            Inj_IndBitFlip     => NiIn.InjIndFlip,
            Inj_IndValid       => NiIn.InjIndValid
        );

    -- Model of the broadcast slot: a code is taken when ready; with DlDiscard it is discarded (not in Run)
    TxDisc <= TxValid and NiIn.DlReady and NiIn.DlDiscard;

    p_log : process (LinkClk, UserClk) is
        variable Char_v : TbChar_t;
        variable Out_v  : NiOut_t := NiOutInit_c;

        procedure logInd (
            kind  : std_logic_vector(1 downto 0);
            value : std_logic_vector) is
        begin
            Char_v      := TbCharInit_c;
            Char_v.Kind := TbBc;
            Char_v.Data := kind & std_logic_vector(resize(unsigned(value), 6));
            Char_v.T    := now;
            FarEnd_v.rxPush(LogInd_g, Char_v);
        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        if rising_edge(LinkClk) then
            if TxValid = '1' and NiIn.DlReady = '1' and NiIn.DlDiscard = '0' and Rst = '0' then
                Char_v      := TbCharInit_c;
                Char_v.Kind := TbBc;
                Char_v.Data := TxData;
                Char_v.T    := now;
                FarEnd_v.rxPush(LogTx_g, Char_v);
            end if;
            if EvTcValid = '1' then
                Out_v.CntTcValid := Out_v.CntTcValid + 1;
            end if;
            if EvTcInv = '1' then
                Out_v.CntTcInv := Out_v.CntTcInv + 1;
            end if;
            if EvIntRx = '1' then
                Out_v.CntIntRx := Out_v.CntIntRx + 1;
            end if;
            if EvAckRx = '1' then
                Out_v.CntAckRx   := Out_v.CntAckRx + 1;
                Out_v.LastAckIid := EvAckIid;
            end if;
            if EvIntDisc = '1' then
                Out_v.CntIntDisc := Out_v.CntIntDisc + 1;
            end if;
            if EvAckDisc = '1' then
                Out_v.CntAckDisc := Out_v.CntAckDisc + 1;
            end if;
            if EvIgnored = '1' then
                Out_v.CntIgnored := Out_v.CntIgnored + 1;
            end if;
            if EvIndOvf = '1' then
                Out_v.CntIndOvf := Out_v.CntIndOvf + 1;
            end if;
            if ReqSec = '1' then
                Out_v.CntReqSec := Out_v.CntReqSec + 1;
            end if;
            if ReqDed = '1' then
                Out_v.CntReqDed := Out_v.CntReqDed + 1;
            end if;
            Out_v.TimeCode  := TimeCode;
            Out_v.IntActive := IntActive;
        end if;
        if rising_edge(UserClk) then
            if MTcValid = '1' and NiIn.IndReady = '1' then
                logInd("00", MTcData);
            end if;
            if MIntValid = '1' and NiIn.IndReady = '1' then
                logInd("01", MIntData);
            end if;
            if MAckValid = '1' and NiIn.IndReady = '1' then
                logInd("10", MAckData);
            end if;
            if IndSec = '1' then
                Out_v.CntIndSec := Out_v.CntIndSec + 1;
            end if;
            if IndDed = '1' then
                Out_v.CntIndDed := Out_v.CntIndDed + 1;
            end if;
        end if;
        Out_v.TcReady  := TcReady;
        Out_v.IntReady := IntReady;
        Out_v.AckReady := AckReady;
        NiOut          <= Out_v;
    end process;

end architecture;
