---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the MIB: owr_mib with LinkClk 100 MHz, UserClk 83.3 MHz and a MgmtClk of
-- configurable period, the AXI4-Lite VVC, and observers of the configuration outputs, the command
-- pulses and the injection commands.
--
-- Documentation: hdl/owr_mib/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_vvc_framework;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.owr_pkg.all;
    use work.owr_mib_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_mib_th is
    generic (
        MgmtHalfPeriod_g : time := 3 ns
    );
    port (
        LinkClk : out   std_logic;
        UserClk : out   std_logic;
        MgmtClk : out   std_logic;
        Rst     : in    std_logic;
        MibIn   : in    MibIn_t;
        MibOut  : out   MibOut_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_mib_th is

    signal LinkClk_i     : std_logic := '0';
    signal UserClk_i     : std_logic := '0';
    signal MgmtClk_i     : std_logic := '0';
    signal ArAddr        : std_logic_vector(7 downto 0);
    signal ArValid       : std_logic;
    signal ArReady       : std_logic;
    signal AwAddr        : std_logic_vector(7 downto 0);
    signal AwValid       : std_logic;
    signal AwReady       : std_logic;
    signal WData         : std_logic_vector(31 downto 0);
    signal WStrb         : std_logic_vector(3 downto 0);
    signal WValid        : std_logic;
    signal WReady        : std_logic;
    signal BResp         : std_logic_vector(1 downto 0);
    signal BValid        : std_logic;
    signal BReady        : std_logic;
    signal RData         : std_logic_vector(31 downto 0);
    signal RResp         : std_logic_vector(1 downto 0);
    signal RValid        : std_logic;
    signal RReady        : std_logic;
    signal PortReset     : std_logic;
    signal LinkDisabled  : std_logic;
    signal LinkStart     : std_logic;
    signal AutoStart     : std_logic;
    signal DriverEn      : std_logic;
    signal ReceiverEn    : std_logic;
    signal Loopback      : std_logic;
    signal RunDiv        : std_logic_vector(7 downto 0);
    signal AckMode       : std_logic;
    signal IntTick       : std_logic_vector(15 downto 0);
    signal IntHoldoff    : std_logic_vector(15 downto 0);
    signal AckDelay      : std_logic_vector(15 downto 0);
    signal TcValid       : std_logic;
    signal TcValue       : std_logic_vector(5 downto 0);
    signal IntValid      : std_logic;
    signal IntIid        : std_logic_vector(4 downto 0);
    signal AckValid      : std_logic;
    signal AckIid        : std_logic_vector(4 downto 0);
    signal Irq           : std_logic;
    signal InjTxFlip     : std_logic_vector(eccCodewordWidth(9) - 1 downto 0);
    signal InjTxValid    : std_logic;
    signal InjRxFlip     : std_logic_vector(eccCodewordWidth(9) - 1 downto 0);
    signal InjRxValid    : std_logic;
    signal InjBcReqFlip  : std_logic_vector(eccCodewordWidth(8) - 1 downto 0);
    signal InjBcReqValid : std_logic;
    signal InjBcIndFlip  : std_logic_vector(eccCodewordWidth(8) - 1 downto 0);
    signal InjBcIndValid : std_logic;

    function ones (vec : std_logic_vector) return natural is
        variable Cnt_v : natural := 0;
    begin

        for i in vec'range loop
            if vec(i) = '1' then
                Cnt_v := Cnt_v + 1;
            end if;
        end loop;

        return Cnt_v;
    end function;

begin

    i_uvvm : entity uvvm_vvc_framework.ti_uvvm_engine;

    LinkClk_i <= not LinkClk_i after 5 ns;
    UserClk_i <= not UserClk_i after 6 ns;
    MgmtClk_i <= not MgmtClk_i after MgmtHalfPeriod_g;
    LinkClk   <= LinkClk_i;
    UserClk   <= UserClk_i;
    MgmtClk   <= MgmtClk_i;

    i_dut : entity work.owr_mib
        generic map (
            LinkClkFreq_g   => 100.0e6,
            TxFifoDepth_g   => 64,
            RxFifoDepth_g   => 128,
            TimeCodes_g     => true,
            Interrupts_g    => true,
            IntTimerWidth_g => 16,
            LinkDisabled_g  => false,
            LinkStart_g     => true,
            AutoStart_g     => false,
            RunDiv_g        => 4
        )
        port map (
            MgmtClk           => MgmtClk_i,
            MgmtRst           => Rst,
            S_AxiLite_ArAddr  => ArAddr,
            S_AxiLite_ArValid => ArValid,
            S_AxiLite_ArReady => ArReady,
            S_AxiLite_AwAddr  => AwAddr,
            S_AxiLite_AwValid => AwValid,
            S_AxiLite_AwReady => AwReady,
            S_AxiLite_WData   => WData,
            S_AxiLite_WStrb   => WStrb,
            S_AxiLite_WValid  => WValid,
            S_AxiLite_WReady  => WReady,
            S_AxiLite_BResp   => BResp,
            S_AxiLite_BValid  => BValid,
            S_AxiLite_BReady  => BReady,
            S_AxiLite_RData   => RData,
            S_AxiLite_RResp   => RResp,
            S_AxiLite_RValid  => RValid,
            S_AxiLite_RReady  => RReady,
            Irq               => Irq,
            Clk               => LinkClk_i,
            Rst               => Rst,
            UserClk           => UserClk_i,
            UserRst           => Rst,
            Cfg_PortReset     => PortReset,
            Cfg_LinkDisabled  => LinkDisabled,
            Cfg_LinkStart     => LinkStart,
            Cfg_AutoStart     => AutoStart,
            Cfg_DriverEn      => DriverEn,
            Cfg_ReceiverEn    => ReceiverEn,
            Cfg_Loopback      => Loopback,
            Cfg_RunDiv        => RunDiv,
            Cfg_AckMode       => AckMode,
            Cfg_IntTick       => IntTick,
            Cfg_IntHoldoff    => IntHoldoff,
            Cfg_AckDelay      => AckDelay,
            Mib_TcValid       => TcValid,
            Mib_TcValue       => TcValue,
            Mib_IntValid      => IntValid,
            Mib_IntIid        => IntIid,
            Mib_AckValid      => AckValid,
            Mib_AckIid        => AckIid,
            Stat_State        => MibIn.State,
            Stat_Recovery     => MibIn.Recovery,
            Stat_GotNull      => MibIn.GotNull,
            Stat_Spill        => MibIn.Spill,
            Stat_Cause        => MibIn.Cause,
            Stat_TxCredit     => MibIn.TxCredit,
            Stat_RxCredit     => MibIn.RxCredit,
            Stat_TxLevel      => MibIn.TxLevel,
            Stat_RxLevel      => MibIn.RxLevel,
            Stat_TimeCode     => MibIn.TimeCode,
            Stat_IntActive    => MibIn.IntActive,
            Ev_Disconnect     => MibIn.Ev(0),
            Ev_ParityErr      => MibIn.Ev(1),
            Ev_EscErr         => MibIn.Ev(2),
            Ev_CreditErr      => MibIn.Ev(3),
            Ev_TcValid        => MibIn.Ev(4),
            Ev_TcInvalid      => MibIn.Ev(5),
            Ev_IntRx          => MibIn.Ev(6),
            Ev_AckRx          => MibIn.Ev(7),
            Ev_AckRxIid       => MibIn.AckIid,
            Ev_BcDiscarded    => MibIn.Ev(8),
            Ev_BcIgnored      => MibIn.Ev(9),
            Ev_IntReqDisc     => MibIn.Ev(10),
            Ev_AckReqDisc     => MibIn.Ev(11),
            Ev_IndOverflow    => MibIn.Ev(12),
            Ev_RxOverflow     => MibIn.Ev(13),
            Ecc_TxSec         => MibIn.EccTx(0),
            Ecc_TxDed         => MibIn.EccTx(1),
            Ecc_RxSec         => MibIn.EccRx(0),
            Ecc_RxDed         => MibIn.EccRx(1),
            Ecc_BcReqSec      => MibIn.EccBcReq(0),
            Ecc_BcReqDed      => MibIn.EccBcReq(1),
            Ecc_BcIndSec      => MibIn.EccBcInd(0),
            Ecc_BcIndDed      => MibIn.EccBcInd(1),
            Inj_TxBitFlip     => InjTxFlip,
            Inj_TxValid       => InjTxValid,
            Inj_RxBitFlip     => InjRxFlip,
            Inj_RxValid       => InjRxValid,
            Inj_BcReqBitFlip  => InjBcReqFlip,
            Inj_BcReqValid    => InjBcReqValid,
            Inj_BcIndBitFlip  => InjBcIndFlip,
            Inj_BcIndValid    => InjBcIndValid
        );

    i_axi : entity work.owr_tb_axilite_master
        generic map (
            InstanceIdx_g => Axi_c,
            AddrWidth_g   => 8
        )
        port map (
            Clk     => MgmtClk_i,
            ArAddr  => ArAddr,
            ArValid => ArValid,
            ArReady => ArReady,
            AwAddr  => AwAddr,
            AwValid => AwValid,
            AwReady => AwReady,
            WData   => WData,
            WStrb   => WStrb,
            WValid  => WValid,
            WReady  => WReady,
            BResp   => BResp,
            BValid  => BValid,
            BReady  => BReady,
            RData   => RData,
            RResp   => RResp,
            RValid  => RValid,
            RReady  => RReady
        );

    -- Observers
    p_obs : process (LinkClk_i, UserClk_i) is
        variable Out_v : MibOut_t;
    begin
        if rising_edge(LinkClk_i) then
            if Rst = '1' then
                Out_v.CntPortReset := 0;
                Out_v.CntTc        := 0;
                Out_v.CntInt       := 0;
                Out_v.CntAck       := 0;
                Out_v.CntInjRx     := 0;
                Out_v.CntInjBcInd  := 0;
            else
                if PortReset = '1' then
                    Out_v.CntPortReset := Out_v.CntPortReset + 1;
                end if;
                if TcValid = '1' then
                    Out_v.CntTc  := Out_v.CntTc + 1;
                    Out_v.LastTc := TcValue;
                end if;
                if IntValid = '1' then
                    Out_v.CntInt  := Out_v.CntInt + 1;
                    Out_v.LastInt := IntIid;
                end if;
                if AckValid = '1' then
                    Out_v.CntAck  := Out_v.CntAck + 1;
                    Out_v.LastAck := AckIid;
                end if;
                if InjRxValid = '1' then
                    Out_v.CntInjRx  := Out_v.CntInjRx + 1;
                    Out_v.BitsInjRx := ones(InjRxFlip);
                end if;
                if InjBcIndValid = '1' then
                    Out_v.CntInjBcInd  := Out_v.CntInjBcInd + 1;
                    Out_v.BitsInjBcInd := ones(InjBcIndFlip);
                end if;
            end if;
        end if;
        if rising_edge(UserClk_i) then
            if Rst = '1' then
                Out_v.CntInjTx    := 0;
                Out_v.CntInjBcReq := 0;
            else
                if InjTxValid = '1' then
                    Out_v.CntInjTx  := Out_v.CntInjTx + 1;
                    Out_v.BitsInjTx := ones(InjTxFlip);
                end if;
                if InjBcReqValid = '1' then
                    Out_v.CntInjBcReq  := Out_v.CntInjBcReq + 1;
                    Out_v.BitsInjBcReq := ones(InjBcReqFlip);
                end if;
            end if;
        end if;
        Out_v.LinkDisabled := LinkDisabled;
        Out_v.LinkStart    := LinkStart;
        Out_v.AutoStart    := AutoStart;
        Out_v.DriverEn     := DriverEn;
        Out_v.ReceiverEn   := ReceiverEn;
        Out_v.Loopback     := Loopback;
        Out_v.RunDiv       := RunDiv;
        Out_v.AckMode      := AckMode;
        Out_v.IntTick      := IntTick;
        Out_v.IntHoldoff   := IntHoldoff;
        Out_v.AckDelay     := AckDelay;
        Out_v.Irq          := Irq;
        MibOut             <= Out_v;
    end process;

end architecture;
