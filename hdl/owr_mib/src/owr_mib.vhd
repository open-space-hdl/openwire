---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Management Information Base of OpenWire (ECSS-E-ST-50-12C Rev.1 clauses 5.7 and 6.5): register
-- bridge from AXI4-Lite in MgmtClk (MG-2), register file and EDAC monitor in LinkClk (MG-1, MG-3)
-- and the crossings of the EDAC events and injection commands of the FIFOs.
--
-- Documentation: hdl/owr_mib/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.owr_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_mib is
    generic (
        LinkClkFreq_g     : real                    := 100.0e6;
        TxFifoDepth_g     : positive                := 64;
        RxFifoDepth_g     : positive                := 64;
        TimeCodes_g       : boolean                 := true;
        Interrupts_g      : boolean                 := true;
        IntTimerWidth_g   : positive range 1 to 30  := 16;
        LinkDisabled_g    : boolean                 := false;
        LinkStart_g       : boolean                 := false;
        AutoStart_g       : boolean                 := false;
        RunDiv_g          : positive range 1 to 255 := 1;
        ReadTimeoutClks_g : positive                := 1000
    );
    port (
        -- Management clock domain: AXI4-Lite and interrupt
        MgmtClk           : in    std_logic;
        MgmtRst           : in    std_logic;
        S_AxiLite_ArAddr  : in    std_logic_vector(7 downto 0);
        S_AxiLite_ArValid : in    std_logic;
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(7 downto 0);
        S_AxiLite_AwValid : in    std_logic;
        S_AxiLite_AwReady : out   std_logic;
        S_AxiLite_WData   : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb   : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid  : in    std_logic;
        S_AxiLite_WReady  : out   std_logic;
        S_AxiLite_BResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid  : out   std_logic;
        S_AxiLite_BReady  : in    std_logic;
        S_AxiLite_RData   : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid  : out   std_logic;
        S_AxiLite_RReady  : in    std_logic;
        Irq               : out   std_logic;
        -- Link clock domain
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        -- User clock domain (EDAC of the user sides of the FIFOs)
        UserClk           : in    std_logic;
        UserRst           : in    std_logic;
        -- Configuration and control (Clk)
        Cfg_PortReset     : out   std_logic;
        Cfg_LinkDisabled  : out   std_logic;
        Cfg_LinkStart     : out   std_logic;
        Cfg_AutoStart     : out   std_logic;
        Cfg_DriverEn      : out   std_logic;
        Cfg_ReceiverEn    : out   std_logic;
        Cfg_Loopback      : out   std_logic;
        Cfg_RunDiv        : out   std_logic_vector(7 downto 0);
        Cfg_AckMode       : out   std_logic;
        Cfg_IntTick       : out   std_logic_vector(15 downto 0);
        Cfg_IntHoldoff    : out   std_logic_vector(IntTimerWidth_g - 1 downto 0);
        Cfg_AckDelay      : out   std_logic_vector(IntTimerWidth_g - 1 downto 0);
        Mib_TcValid       : out   std_logic;
        Mib_TcValue       : out   std_logic_vector(5 downto 0);
        Mib_IntValid      : out   std_logic;
        Mib_IntIid        : out   std_logic_vector(4 downto 0);
        Mib_AckValid      : out   std_logic;
        Mib_AckIid        : out   std_logic_vector(4 downto 0);
        -- Status and events (Clk)
        Stat_State        : in    LinkState_t;
        Stat_Recovery     : in    std_logic;
        Stat_GotNull      : in    std_logic;
        Stat_Spill        : in    std_logic;
        Stat_Cause        : in    ErrCause_t;
        Stat_TxCredit     : in    std_logic_vector(5 downto 0);
        Stat_RxCredit     : in    std_logic_vector(5 downto 0);
        Stat_TxLevel      : in    std_logic_vector(15 downto 0);
        Stat_RxLevel      : in    std_logic_vector(15 downto 0);
        Stat_TimeCode     : in    std_logic_vector(5 downto 0);
        Stat_IntActive    : in    std_logic_vector(31 downto 0);
        Ev_Disconnect     : in    std_logic;
        Ev_ParityErr      : in    std_logic;
        Ev_EscErr         : in    std_logic;
        Ev_CreditErr      : in    std_logic;
        Ev_TcValid        : in    std_logic;
        Ev_TcInvalid      : in    std_logic;
        Ev_IntRx          : in    std_logic;
        Ev_AckRx          : in    std_logic;
        Ev_AckRxIid       : in    std_logic_vector(4 downto 0);
        Ev_BcDiscarded    : in    std_logic;
        Ev_BcIgnored      : in    std_logic;
        Ev_IntReqDisc     : in    std_logic;
        Ev_AckReqDisc     : in    std_logic;
        Ev_IndOverflow    : in    std_logic;
        Ev_RxOverflow     : in    std_logic;
        -- EDAC of the FIFOs of the Data Link and Network layers: events on the read side, injection on the write side
        Ecc_TxSec         : in    std_logic; -- Clk
        Ecc_TxDed         : in    std_logic; -- Clk
        Ecc_RxSec         : in    std_logic; -- UserClk
        Ecc_RxDed         : in    std_logic; -- UserClk
        Ecc_BcReqSec      : in    std_logic; -- Clk
        Ecc_BcReqDed      : in    std_logic; -- Clk
        Ecc_BcIndSec      : in    std_logic; -- UserClk
        Ecc_BcIndDed      : in    std_logic; -- UserClk
        Inj_TxBitFlip     : out   std_logic_vector(eccCodewordWidth(9) - 1 downto 0); -- UserClk
        Inj_TxValid       : out   std_logic;                                          -- UserClk
        Inj_RxBitFlip     : out   std_logic_vector(eccCodewordWidth(9) - 1 downto 0); -- Clk
        Inj_RxValid       : out   std_logic;                                          -- Clk
        Inj_BcReqBitFlip  : out   std_logic_vector(eccCodewordWidth(8) - 1 downto 0); -- UserClk
        Inj_BcReqValid    : out   std_logic;                                          -- UserClk
        Inj_BcIndBitFlip  : out   std_logic_vector(eccCodewordWidth(8) - 1 downto 0); -- Clk
        Inj_BcIndValid    : out   std_logic                                           -- Clk
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_mib is

    -- Flip patterns of the injection: one or two data bits of the codeword
    function flipPattern (
        width  : positive;
        double : std_logic) return std_logic_vector is
        variable Res_v : std_logic_vector(width - 1 downto 0) := (others => '0');
    begin
        Res_v(3) := '1';
        if double = '1' then
            Res_v(5) := '1';
        end if;
        return Res_v;
    end function;

    -- Register bus
    signal RbAddr    : std_logic_vector(7 downto 0);
    signal RbWr      : std_logic;
    signal RbByteEna : std_logic_vector(3 downto 0);
    signal RbWrData  : std_logic_vector(31 downto 0);
    signal RbRd      : std_logic;
    signal RbRdData  : std_logic_vector(31 downto 0);
    signal RbRdValid : std_logic;
    -- EDAC
    signal EccSec    : std_logic_vector(5 downto 0);
    signal EccDed    : std_logic_vector(5 downto 0);
    signal InjValid  : std_logic_vector(5 downto 0);
    signal InjDouble : std_logic;
    signal ReqSec    : std_logic;
    signal ReqDed    : std_logic;
    signal RspSec    : std_logic;
    signal RspDed    : std_logic;
    signal UserEvt   : std_logic_vector(3 downto 0);
    signal MgmtEvt   : std_logic_vector(1 downto 0);
    signal ToUser    : std_logic_vector(3 downto 0);
    signal AtUser    : std_logic_vector(3 downto 0);
    signal ToMgmt    : std_logic_vector(1 downto 0);
    signal AtMgmt    : std_logic_vector(1 downto 0);
    signal InjReq    : std_logic;
    signal IrqLink   : std_logic;
    signal IrqMgmt   : std_logic_vector(0 downto 0);

begin

    -- MG-2 register bridge
    i_bridge : entity work.owr_mib_bridge
        generic map (
            ReadTimeoutClks_g => ReadTimeoutClks_g
        )
        port map (
            MgmtClk           => MgmtClk,
            MgmtRst           => MgmtRst,
            S_AxiLite_ArAddr  => S_AxiLite_ArAddr,
            S_AxiLite_ArValid => S_AxiLite_ArValid,
            S_AxiLite_ArReady => S_AxiLite_ArReady,
            S_AxiLite_AwAddr  => S_AxiLite_AwAddr,
            S_AxiLite_AwValid => S_AxiLite_AwValid,
            S_AxiLite_AwReady => S_AxiLite_AwReady,
            S_AxiLite_WData   => S_AxiLite_WData,
            S_AxiLite_WStrb   => S_AxiLite_WStrb,
            S_AxiLite_WValid  => S_AxiLite_WValid,
            S_AxiLite_WReady  => S_AxiLite_WReady,
            S_AxiLite_BResp   => S_AxiLite_BResp,
            S_AxiLite_BValid  => S_AxiLite_BValid,
            S_AxiLite_BReady  => S_AxiLite_BReady,
            S_AxiLite_RData   => S_AxiLite_RData,
            S_AxiLite_RResp   => S_AxiLite_RResp,
            S_AxiLite_RValid  => S_AxiLite_RValid,
            S_AxiLite_RReady  => S_AxiLite_RReady,
            Clk               => Clk,
            Rst               => Rst,
            Rb_Addr           => RbAddr,
            Rb_Wr             => RbWr,
            Rb_ByteEna        => RbByteEna,
            Rb_WrData         => RbWrData,
            Rb_Rd             => RbRd,
            Rb_RdData         => RbRdData,
            Rb_RdValid        => RbRdValid,
            Ecc_ReqSec        => ReqSec,
            Ecc_ReqDed        => ReqDed,
            Ecc_RspSec        => RspSec,
            Ecc_RspDed        => RspDed,
            Inj_ReqBitFlip    => flipPattern(eccCodewordWidth(45), AtMgmt(1)),
            Inj_ReqValid      => InjReq,
            Inj_RspBitFlip    => flipPattern(eccCodewordWidth(34), InjDouble),
            Inj_RspValid      => InjValid(5)
        );

    -- MG-1 register file and MG-3 EDAC monitor
    i_regs : entity work.owr_mib_regs
        generic map (
            LinkClkFreq_g   => LinkClkFreq_g,
            TxFifoDepth_g   => TxFifoDepth_g,
            RxFifoDepth_g   => RxFifoDepth_g,
            TimeCodes_g     => TimeCodes_g,
            Interrupts_g    => Interrupts_g,
            IntTimerWidth_g => IntTimerWidth_g,
            LinkDisabled_g  => LinkDisabled_g,
            LinkStart_g     => LinkStart_g,
            AutoStart_g     => AutoStart_g,
            RunDiv_g        => RunDiv_g
        )
        port map (
            Clk              => Clk,
            Rst              => Rst,
            Rb_Addr          => RbAddr,
            Rb_Wr            => RbWr,
            Rb_ByteEna       => RbByteEna,
            Rb_WrData        => RbWrData,
            Rb_Rd            => RbRd,
            Rb_RdData        => RbRdData,
            Rb_RdValid       => RbRdValid,
            Cfg_PortReset    => Cfg_PortReset,
            Cfg_LinkDisabled => Cfg_LinkDisabled,
            Cfg_LinkStart    => Cfg_LinkStart,
            Cfg_AutoStart    => Cfg_AutoStart,
            Cfg_DriverEn     => Cfg_DriverEn,
            Cfg_ReceiverEn   => Cfg_ReceiverEn,
            Cfg_Loopback     => Cfg_Loopback,
            Cfg_RunDiv       => Cfg_RunDiv,
            Cfg_AckMode      => Cfg_AckMode,
            Cfg_IntTick      => Cfg_IntTick,
            Cfg_IntHoldoff   => Cfg_IntHoldoff,
            Cfg_AckDelay     => Cfg_AckDelay,
            Mib_TcValid      => Mib_TcValid,
            Mib_TcValue      => Mib_TcValue,
            Mib_IntValid     => Mib_IntValid,
            Mib_IntIid       => Mib_IntIid,
            Mib_AckValid     => Mib_AckValid,
            Mib_AckIid       => Mib_AckIid,
            Stat_State       => Stat_State,
            Stat_Recovery    => Stat_Recovery,
            Stat_GotNull     => Stat_GotNull,
            Stat_Spill       => Stat_Spill,
            Stat_Cause       => Stat_Cause,
            Stat_TxCredit    => Stat_TxCredit,
            Stat_RxCredit    => Stat_RxCredit,
            Stat_TxLevel     => Stat_TxLevel,
            Stat_RxLevel     => Stat_RxLevel,
            Stat_TimeCode    => Stat_TimeCode,
            Stat_IntActive   => Stat_IntActive,
            Ev_Disconnect    => Ev_Disconnect,
            Ev_ParityErr     => Ev_ParityErr,
            Ev_EscErr        => Ev_EscErr,
            Ev_CreditErr     => Ev_CreditErr,
            Ev_TcValid       => Ev_TcValid,
            Ev_TcInvalid     => Ev_TcInvalid,
            Ev_IntRx         => Ev_IntRx,
            Ev_AckRx         => Ev_AckRx,
            Ev_AckRxIid      => Ev_AckRxIid,
            Ev_BcDiscarded   => Ev_BcDiscarded,
            Ev_BcIgnored     => Ev_BcIgnored,
            Ev_IntReqDisc    => Ev_IntReqDisc,
            Ev_AckReqDisc    => Ev_AckReqDisc,
            Ev_IndOverflow   => Ev_IndOverflow,
            Ev_RxOverflow    => Ev_RxOverflow,
            Ecc_Sec          => EccSec,
            Ecc_Ded          => EccDed,
            Inj_Valid        => InjValid,
            Inj_Double       => InjDouble,
            Irq              => IrqLink
        );

    -----------------------------------------------------------------------------------------------
    -- EDAC events of the read sides in UserClk and MgmtClk
    -----------------------------------------------------------------------------------------------
    UserEvt <= Ecc_BcIndDed & Ecc_BcIndSec & Ecc_RxDed & Ecc_RxSec;

    i_cc_user_evt : entity work.owr_cc_pulse
        generic map (
            NumPulses_g => 4
        )
        port map (
            In_Clk    => UserClk,
            In_Rst    => UserRst,
            In_Pulse  => UserEvt,
            Out_Clk   => Clk,
            Out_Rst   => Rst,
            Out_Pulse => ToUser
        );

    MgmtEvt <= RspDed & RspSec;

    i_cc_mgmt_evt : entity work.owr_cc_pulse
        generic map (
            NumPulses_g => 2
        )
        port map (
            In_Clk    => MgmtClk,
            In_Rst    => MgmtRst,
            In_Pulse  => MgmtEvt,
            Out_Clk   => Clk,
            Out_Rst   => Rst,
            Out_Pulse => ToMgmt
        );

    -- Channels: 0 transmit FIFO, 1 receive FIFO, 2 broadcast requests, 3 broadcast indications, 4 register requests,
    -- 5 register responses
    EccSec <= ToMgmt(0) & ReqSec & ToUser(2) & Ecc_BcReqSec & ToUser(0) & Ecc_TxSec;
    EccDed <= ToMgmt(1) & ReqDed & ToUser(3) & Ecc_BcReqDed & ToUser(1) & Ecc_TxDed;

    -----------------------------------------------------------------------------------------------
    -- Injection commands to the write sides
    -----------------------------------------------------------------------------------------------
    -- To UserClk: single and double for the transmit FIFO and the broadcast request FIFO
    i_cc_user_inj : entity work.owr_cc_pulse
        generic map (
            NumPulses_g => 4
        )
        port map (
            In_Clk    => Clk,
            In_Rst    => Rst,
            In_Pulse  => (InjValid(2) and InjDouble) & (InjValid(2) and not InjDouble) &
                         (InjValid(0) and InjDouble) & (InjValid(0) and not InjDouble),
            Out_Clk   => UserClk,
            Out_Rst   => UserRst,
            Out_Pulse => AtUser
        );

    Inj_TxValid      <= AtUser(0) or AtUser(1);
    Inj_TxBitFlip    <= flipPattern(eccCodewordWidth(9), AtUser(1));
    Inj_BcReqValid   <= AtUser(2) or AtUser(3);
    Inj_BcReqBitFlip <= flipPattern(eccCodewordWidth(8), AtUser(3));

    -- To MgmtClk: single and double for the register request FIFO
    i_cc_mgmt_inj : entity work.owr_cc_pulse
        generic map (
            NumPulses_g => 2
        )
        port map (
            In_Clk    => Clk,
            In_Rst    => Rst,
            In_Pulse  => (InjValid(4) and InjDouble) & (InjValid(4) and not InjDouble),
            Out_Clk   => MgmtClk,
            Out_Rst   => MgmtRst,
            Out_Pulse => AtMgmt
        );

    InjReq <= AtMgmt(0) or AtMgmt(1);

    -- In LinkClk: receive FIFO, broadcast indication FIFO (the register response FIFO is in the bridge)
    Inj_RxValid      <= InjValid(1);
    Inj_RxBitFlip    <= flipPattern(eccCodewordWidth(9), InjDouble);
    Inj_BcIndValid   <= InjValid(3);
    Inj_BcIndBitFlip <= flipPattern(eccCodewordWidth(8), InjDouble);

    -- Interrupt in MgmtClk
    i_cc_irq : entity olo.olo_ft_cc_bits
        generic map (
            Width_g => 1
        )
        port map (
            In_Clk     => Clk,
            In_Rst     => Rst,
            In_Data(0) => IrqLink,
            Out_Clk    => MgmtClk,
            Out_Rst    => MgmtRst,
            Out_Data   => IrqMgmt
        );

    Irq <= IrqMgmt(0);

end architecture;
