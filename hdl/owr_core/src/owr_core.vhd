---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- OpenWire core: SpaceWire port with a node interface (ECSS-E-ST-50-12C Rev.1): packet, time-code
-- and distributed interrupt services on AXI4-Stream, the Management Information Base on AXI4-Lite
-- and the data and strobe signals for the line drivers and receivers of the target.
--
-- Documentation: hdl/owr_core/docs/architecture.md, docs/user_guide.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.owr_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_core is
    generic (
        LinkClkFreq_g   : real                    := 100.0e6;
        TxFifoDepth_g   : positive                := 64;
        RxFifoDepth_g   : positive                := 64;
        TimeCodes_g     : boolean                 := true;
        Interrupts_g    : boolean                 := true;
        IntTimerWidth_g : positive range 1 to 30  := 16;
        LinkDisabled_g  : boolean                 := false;
        LinkStart_g     : boolean                 := false;
        AutoStart_g     : boolean                 := false;
        RunDiv_g        : positive range 1 to 255 := 1;
        SyncStages_g    : positive range 2 to 4   := 2
    );
    port (
        -- Asynchronous reset (high active), clocks
        Rst               : in    std_logic;
        UserClk           : in    std_logic;
        LinkClk           : in    std_logic;
        MgmtClk           : in    std_logic;
        -- Packet service (UserClk): one N-Char per beat, a beat with TLast is the end of packet marker
        -- (TData(0) = '0' EOP, '1' EEP)
        S_Pkt_TData       : in    std_logic_vector(7 downto 0);
        S_Pkt_TLast       : in    std_logic;
        S_Pkt_TValid      : in    std_logic;
        S_Pkt_TReady      : out   std_logic;
        M_Pkt_TData       : out   std_logic_vector(7 downto 0);
        M_Pkt_TLast       : out   std_logic;
        M_Pkt_TValid      : out   std_logic;
        M_Pkt_TReady      : in    std_logic;
        -- Time-code service (UserClk)
        S_Tc_TData        : in    std_logic_vector(5 downto 0) := (others => '0');
        S_Tc_TValid       : in    std_logic                    := '0';
        S_Tc_TReady       : out   std_logic;
        M_Tc_TData        : out   std_logic_vector(5 downto 0);
        M_Tc_TValid       : out   std_logic;
        M_Tc_TReady       : in    std_logic                    := '1';
        -- Distributed interrupt service (UserClk)
        S_Int_TData       : in    std_logic_vector(4 downto 0) := (others => '0');
        S_Int_TValid      : in    std_logic                    := '0';
        S_Int_TReady      : out   std_logic;
        S_IntAck_TData    : in    std_logic_vector(4 downto 0) := (others => '0');
        S_IntAck_TValid   : in    std_logic                    := '0';
        S_IntAck_TReady   : out   std_logic;
        M_Int_TData       : out   std_logic_vector(4 downto 0);
        M_Int_TValid      : out   std_logic;
        M_Int_TReady      : in    std_logic                    := '1';
        M_IntAck_TData    : out   std_logic_vector(4 downto 0);
        M_IntAck_TValid   : out   std_logic;
        M_IntAck_TReady   : in    std_logic                    := '1';
        -- Management Information Base (MgmtClk)
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
        -- Line drivers and receivers (LinkClk; the inputs are asynchronous)
        Spw_DOut          : out   std_logic;
        Spw_SOut          : out   std_logic;
        Spw_DIn           : in    std_logic;
        Spw_SIn           : in    std_logic;
        Phy_TxEn          : out   std_logic;
        Phy_RxEn          : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_core is

    -- Resets per domain
    signal UserRst : std_logic;
    signal LinkRst : std_logic;
    signal MgmtRst : std_logic;

    -- Encoding layer
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

    -- Packet service
    signal TxNChar : NChar_t;
    signal RxNChar : NChar_t;

    -- Broadcast codes between the Network and Data Link layers
    signal TxBcData  : std_logic_vector(7 downto 0);
    signal TxBcValid : std_logic;
    signal TxBcReady : std_logic;
    signal TxBcDisc  : std_logic;
    signal RxBcData  : std_logic_vector(7 downto 0);
    signal RxBcValid : std_logic;

    -- Configuration
    signal CfgPortReset    : std_logic;
    signal CfgLinkDisabled : std_logic;
    signal CfgLinkStart    : std_logic;
    signal CfgAutoStart    : std_logic;
    signal CfgLoopback     : std_logic;
    signal CfgRunDiv       : std_logic_vector(7 downto 0);
    signal CfgAckMode      : std_logic;
    signal CfgIntTick      : std_logic_vector(15 downto 0);
    signal CfgIntHoldoff   : std_logic_vector(IntTimerWidth_g - 1 downto 0);
    signal CfgAckDelay     : std_logic_vector(IntTimerWidth_g - 1 downto 0);
    signal MibTcValid      : std_logic;
    signal MibTcValue      : std_logic_vector(5 downto 0);
    signal MibIntValid     : std_logic;
    signal MibIntIid       : std_logic_vector(4 downto 0);
    signal MibAckValid     : std_logic;
    signal MibAckIid       : std_logic_vector(4 downto 0);

    -- Status and events
    signal StState     : LinkState_t;
    signal StRecovery  : std_logic;
    signal StCause     : ErrCause_t;
    signal StTxCredit  : std_logic_vector(5 downto 0);
    signal StRxCredit  : std_logic_vector(5 downto 0);
    signal StTxLevel   : std_logic_vector(log2ceil(TxFifoDepth_g + 1) - 1 downto 0);
    signal StRxLevel   : std_logic_vector(log2ceil(RxFifoDepth_g + 1) - 1 downto 0);
    signal StSpill     : std_logic;
    signal StTimeCode  : std_logic_vector(5 downto 0);
    signal StIntActive : std_logic_vector(31 downto 0);
    signal EvCredit    : std_logic;
    signal EvRxOvf     : std_logic;
    signal EvTcValid   : std_logic;
    signal EvTcInvalid : std_logic;
    signal EvIntRx     : std_logic;
    signal EvAckRx     : std_logic;
    signal EvAckRxIid  : std_logic_vector(4 downto 0);
    signal EvIntDisc   : std_logic;
    signal EvAckDisc   : std_logic;
    signal EvIgnored   : std_logic;
    signal EvIndOvf    : std_logic;

    -- EDAC
    signal EccTxSec     : std_logic;
    signal EccTxDed     : std_logic;
    signal EccRxSec     : std_logic;
    signal EccRxDed     : std_logic;
    signal EccBcReqSec  : std_logic;
    signal EccBcReqDed  : std_logic;
    signal EccBcIndSec  : std_logic;
    signal EccBcIndDed  : std_logic;
    signal InjTxFlip    : std_logic_vector(eccCodewordWidth(9) - 1 downto 0);
    signal InjTxValid   : std_logic;
    signal InjRxFlip    : std_logic_vector(eccCodewordWidth(9) - 1 downto 0);
    signal InjRxValid   : std_logic;
    signal InjBcReqFlip : std_logic_vector(eccCodewordWidth(8) - 1 downto 0);
    signal InjBcReqVld  : std_logic;
    signal InjBcIndFlip : std_logic_vector(eccCodewordWidth(8) - 1 downto 0);
    signal InjBcIndVld  : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- MG-4 Clock and reset: the asynchronous reset brought into each domain
    -----------------------------------------------------------------------------------------------
    i_rst_user : entity olo.olo_base_reset_gen
        port map (
            Clk    => UserClk,
            RstOut => UserRst,
            RstIn  => Rst
        );

    i_rst_link : entity olo.olo_base_reset_gen
        port map (
            Clk    => LinkClk,
            RstOut => LinkRst,
            RstIn  => Rst
        );

    i_rst_mgmt : entity olo.olo_base_reset_gen
        port map (
            Clk    => MgmtClk,
            RstOut => MgmtRst,
            RstIn  => Rst
        );

    -----------------------------------------------------------------------------------------------
    -- NI-1 Packet service: one N-Char per beat (ECSS 5.6.2, 6.1.1)
    -----------------------------------------------------------------------------------------------
    TxNChar     <= '1' & "0000000" & S_Pkt_TData(0) when S_Pkt_TLast = '1' else '0' & S_Pkt_TData;
    M_Pkt_TData <= RxNChar(7 downto 0);
    M_Pkt_TLast <= RxNChar(NCharFlagIdx_c);

    -----------------------------------------------------------------------------------------------
    -- Network layer (NI-2 to NI-4)
    -----------------------------------------------------------------------------------------------
    i_ni : entity work.owr_ni
        generic map (
            TimeCodes_g     => TimeCodes_g,
            Interrupts_g    => Interrupts_g,
            IntTimerWidth_g => IntTimerWidth_g
        )
        port map (
            Clk                => LinkClk,
            Rst                => LinkRst,
            UserClk            => UserClk,
            UserRst            => UserRst,
            S_Tc_TData         => S_Tc_TData,
            S_Tc_TValid        => S_Tc_TValid,
            S_Tc_TReady        => S_Tc_TReady,
            S_Int_TData        => S_Int_TData,
            S_Int_TValid       => S_Int_TValid,
            S_Int_TReady       => S_Int_TReady,
            S_Ack_TData        => S_IntAck_TData,
            S_Ack_TValid       => S_IntAck_TValid,
            S_Ack_TReady       => S_IntAck_TReady,
            M_Tc_TData         => M_Tc_TData,
            M_Tc_TValid        => M_Tc_TValid,
            M_Tc_TReady        => M_Tc_TReady,
            M_Int_TData        => M_Int_TData,
            M_Int_TValid       => M_Int_TValid,
            M_Int_TReady       => M_Int_TReady,
            M_Ack_TData        => M_IntAck_TData,
            M_Ack_TValid       => M_IntAck_TValid,
            M_Ack_TReady       => M_IntAck_TReady,
            Mib_TcValid        => MibTcValid,
            Mib_TcValue        => MibTcValue,
            Mib_IntValid       => MibIntValid,
            Mib_IntIid         => MibIntIid,
            Mib_AckValid       => MibAckValid,
            Mib_AckIid         => MibAckIid,
            Cfg_PortReset      => CfgPortReset,
            Cfg_AckMode        => CfgAckMode,
            Cfg_IntTick        => CfgIntTick,
            Cfg_IntHoldoff     => CfgIntHoldoff,
            Cfg_AckDelay       => CfgAckDelay,
            TxBc_Data          => TxBcData,
            TxBc_Valid         => TxBcValid,
            TxBc_Ready         => TxBcReady,
            TxBc_Discarded     => TxBcDisc,
            RxBc_Data          => RxBcData,
            RxBc_Valid         => RxBcValid,
            Stat_TimeCode      => StTimeCode,
            Stat_IntActive     => StIntActive,
            Ev_TcValid         => EvTcValid,
            Ev_TcInvalid       => EvTcInvalid,
            Ev_IntRx           => EvIntRx,
            Ev_AckRx           => EvAckRx,
            Ev_AckRxIid        => EvAckRxIid,
            Ev_IntReqDiscarded => EvIntDisc,
            Ev_AckReqDiscarded => EvAckDisc,
            Ev_BcIgnored       => EvIgnored,
            Ev_IndOverflow     => EvIndOvf,
            Ecc_ReqSec         => EccBcReqSec,
            Ecc_ReqDed         => EccBcReqDed,
            Ecc_IndSec         => EccBcIndSec,
            Ecc_IndDed         => EccBcIndDed,
            Inj_ReqBitFlip     => InjBcReqFlip,
            Inj_ReqValid       => InjBcReqVld,
            Inj_IndBitFlip     => InjBcIndFlip,
            Inj_IndValid       => InjBcIndVld
        );

    -----------------------------------------------------------------------------------------------
    -- Data Link layer (DL-1 to DL-7)
    -----------------------------------------------------------------------------------------------
    i_dl : entity work.owr_dl
        generic map (
            ClkFreq_g     => LinkClkFreq_g,
            TxFifoDepth_g => TxFifoDepth_g,
            RxFifoDepth_g => RxFifoDepth_g
        )
        port map (
            Clk              => LinkClk,
            Rst              => LinkRst,
            UserClk          => UserClk,
            UserRst          => UserRst,
            TxUser_Data      => TxNChar,
            TxUser_Valid     => S_Pkt_TValid,
            TxUser_Ready     => S_Pkt_TReady,
            RxUser_Data      => RxNChar,
            RxUser_Valid     => M_Pkt_TValid,
            RxUser_Ready     => M_Pkt_TReady,
            TxBc_Data        => TxBcData,
            TxBc_Valid       => TxBcValid,
            TxBc_Ready       => TxBcReady,
            TxBc_Discarded   => TxBcDisc,
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
            Cfg_PortReset    => CfgPortReset,
            Cfg_LinkDisabled => CfgLinkDisabled,
            Cfg_LinkStart    => CfgLinkStart,
            Cfg_AutoStart    => CfgAutoStart,
            Stat_State       => StState,
            Stat_Recovery    => StRecovery,
            Stat_Cause       => StCause,
            Stat_TxCredit    => StTxCredit,
            Stat_RxCredit    => StRxCredit,
            Stat_TxLevel     => StTxLevel,
            Stat_RxLevel     => StRxLevel,
            Stat_Spill       => StSpill,
            Ev_CreditErr     => EvCredit,
            Ev_RxOverflow    => EvRxOvf,
            Ecc_TxSec        => EccTxSec,
            Ecc_TxDed        => EccTxDed,
            Ecc_RxSec        => EccRxSec,
            Ecc_RxDed        => EccRxDed,
            Inj_TxBitFlip    => InjTxFlip,
            Inj_TxValid      => InjTxValid,
            Inj_RxBitFlip    => InjRxFlip,
            Inj_RxValid      => InjRxValid
        );

    -----------------------------------------------------------------------------------------------
    -- Encoding layer (EN-1 to EN-3)
    -----------------------------------------------------------------------------------------------
    i_enc : entity work.owr_enc
        generic map (
            ClkFreq_g    => LinkClkFreq_g,
            SyncStages_g => SyncStages_g
        )
        port map (
            Clk           => LinkClk,
            Rst           => LinkRst,
            TxEnable      => TxEnable,
            RxEnable      => RxEnable,
            TxRun         => TxRun,
            Cfg_RunDiv    => CfgRunDiv,
            Cfg_Loopback  => CfgLoopback,
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

    -----------------------------------------------------------------------------------------------
    -- Management Information Base (MG-1 to MG-3)
    -----------------------------------------------------------------------------------------------
    i_mib : entity work.owr_mib
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
            Irq               => Irq,
            Clk               => LinkClk,
            Rst               => LinkRst,
            UserClk           => UserClk,
            UserRst           => UserRst,
            Cfg_PortReset     => CfgPortReset,
            Cfg_LinkDisabled  => CfgLinkDisabled,
            Cfg_LinkStart     => CfgLinkStart,
            Cfg_AutoStart     => CfgAutoStart,
            Cfg_DriverEn      => Phy_TxEn,
            Cfg_ReceiverEn    => Phy_RxEn,
            Cfg_Loopback      => CfgLoopback,
            Cfg_RunDiv        => CfgRunDiv,
            Cfg_AckMode       => CfgAckMode,
            Cfg_IntTick       => CfgIntTick,
            Cfg_IntHoldoff    => CfgIntHoldoff,
            Cfg_AckDelay      => CfgAckDelay,
            Mib_TcValid       => MibTcValid,
            Mib_TcValue       => MibTcValue,
            Mib_IntValid      => MibIntValid,
            Mib_IntIid        => MibIntIid,
            Mib_AckValid      => MibAckValid,
            Mib_AckIid        => MibAckIid,
            Stat_State        => StState,
            Stat_Recovery     => StRecovery,
            Stat_GotNull      => GotNull,
            Stat_Spill        => StSpill,
            Stat_Cause        => StCause,
            Stat_TxCredit     => StTxCredit,
            Stat_RxCredit     => StRxCredit,
            Stat_TxLevel      => std_logic_vector(resize(unsigned(StTxLevel), 16)),
            Stat_RxLevel      => std_logic_vector(resize(unsigned(StRxLevel), 16)),
            Stat_TimeCode     => StTimeCode,
            Stat_IntActive    => StIntActive,
            Ev_Disconnect     => DiscEvt,
            Ev_ParityErr      => ParityErr,
            Ev_EscErr         => EscErr,
            Ev_CreditErr      => EvCredit,
            Ev_TcValid        => EvTcValid,
            Ev_TcInvalid      => EvTcInvalid,
            Ev_IntRx          => EvIntRx,
            Ev_AckRx          => EvAckRx,
            Ev_AckRxIid       => EvAckRxIid,
            Ev_BcDiscarded    => TxBcDisc,
            Ev_BcIgnored      => EvIgnored,
            Ev_IntReqDisc     => EvIntDisc,
            Ev_AckReqDisc     => EvAckDisc,
            Ev_IndOverflow    => EvIndOvf,
            Ev_RxOverflow     => EvRxOvf,
            Ecc_TxSec         => EccTxSec,
            Ecc_TxDed         => EccTxDed,
            Ecc_RxSec         => EccRxSec,
            Ecc_RxDed         => EccRxDed,
            Ecc_BcReqSec      => EccBcReqSec,
            Ecc_BcReqDed      => EccBcReqDed,
            Ecc_BcIndSec      => EccBcIndSec,
            Ecc_BcIndDed      => EccBcIndDed,
            Inj_TxBitFlip     => InjTxFlip,
            Inj_TxValid       => InjTxValid,
            Inj_RxBitFlip     => InjRxFlip,
            Inj_RxValid       => InjRxValid,
            Inj_BcReqBitFlip  => InjBcReqFlip,
            Inj_BcReqValid    => InjBcReqVld,
            Inj_BcIndBitFlip  => InjBcIndFlip,
            Inj_BcIndValid    => InjBcIndVld
        );

end architecture;
