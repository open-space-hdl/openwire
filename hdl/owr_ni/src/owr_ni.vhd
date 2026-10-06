---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Network layer of a SpaceWire node with one end-point (ECSS-E-ST-50-12C Rev.1 clause 5.6):
-- time-code service (NI-2), distributed interrupt service (NI-3) and broadcast code service (NI-4).
-- The packet service (NI-1) is the N-Char stream of the Data Link layer.
--
-- Documentation: hdl/owr_ni/docs/architecture.md

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
entity owr_ni is
    generic (
        TimeCodes_g     : boolean                := true;
        Interrupts_g    : boolean                := true;
        IntTimerWidth_g : positive range 1 to 30 := 16
    );
    port (
        -- Link clock domain
        Clk                : in    std_logic;
        Rst                : in    std_logic;
        -- User clock domain
        UserClk            : in    std_logic;
        UserRst            : in    std_logic;
        -- Broadcast services of the user (UserClk)
        S_Tc_TData         : in    std_logic_vector(5 downto 0);
        S_Tc_TValid        : in    std_logic;
        S_Tc_TReady        : out   std_logic;
        S_Int_TData        : in    std_logic_vector(4 downto 0);
        S_Int_TValid       : in    std_logic;
        S_Int_TReady       : out   std_logic;
        S_Ack_TData        : in    std_logic_vector(4 downto 0);
        S_Ack_TValid       : in    std_logic;
        S_Ack_TReady       : out   std_logic;
        M_Tc_TData         : out   std_logic_vector(5 downto 0);
        M_Tc_TValid        : out   std_logic;
        M_Tc_TReady        : in    std_logic;
        M_Int_TData        : out   std_logic_vector(4 downto 0);
        M_Int_TValid       : out   std_logic;
        M_Int_TReady       : in    std_logic;
        M_Ack_TData        : out   std_logic_vector(4 downto 0);
        M_Ack_TValid       : out   std_logic;
        M_Ack_TReady       : in    std_logic;
        -- MIB: requests, configuration, port reset
        Mib_TcValid        : in    std_logic;
        Mib_TcValue        : in    std_logic_vector(5 downto 0);
        Mib_IntValid       : in    std_logic;
        Mib_IntIid         : in    std_logic_vector(4 downto 0);
        Mib_AckValid       : in    std_logic;
        Mib_AckIid         : in    std_logic_vector(4 downto 0);
        Cfg_PortReset      : in    std_logic;
        Cfg_AckMode        : in    std_logic;
        Cfg_IntTick        : in    std_logic_vector(15 downto 0);
        Cfg_IntHoldoff     : in    std_logic_vector(IntTimerWidth_g - 1 downto 0);
        Cfg_AckDelay       : in    std_logic_vector(IntTimerWidth_g - 1 downto 0);
        -- Data Link layer
        TxBc_Data          : out   std_logic_vector(7 downto 0);
        TxBc_Valid         : out   std_logic;
        TxBc_Ready         : in    std_logic;
        TxBc_Discarded     : in    std_logic;
        RxBc_Data          : in    std_logic_vector(7 downto 0);
        RxBc_Valid         : in    std_logic;
        -- Status and events for the MIB
        Stat_TimeCode      : out   std_logic_vector(5 downto 0);
        Stat_IntActive     : out   std_logic_vector(31 downto 0);
        Ev_TcValid         : out   std_logic;
        Ev_TcInvalid       : out   std_logic;
        Ev_IntRx           : out   std_logic;
        Ev_AckRx           : out   std_logic;
        Ev_AckRxIid        : out   std_logic_vector(4 downto 0);
        Ev_IntReqDiscarded : out   std_logic;
        Ev_AckReqDiscarded : out   std_logic;
        Ev_BcIgnored       : out   std_logic;
        Ev_IndOverflow     : out   std_logic;
        -- EDAC of the FIFOs
        Ecc_ReqSec         : out   std_logic;
        Ecc_ReqDed         : out   std_logic;
        Ecc_IndSec         : out   std_logic; -- UserClk
        Ecc_IndDed         : out   std_logic; -- UserClk
        Inj_ReqBitFlip     : in    std_logic_vector(eccCodewordWidth(8) - 1 downto 0) := (others => '0'); -- UserClk
        Inj_ReqValid       : in    std_logic                                          := '0';               -- UserClk
        Inj_IndBitFlip     : in    std_logic_vector(eccCodewordWidth(8) - 1 downto 0) := (others => '0');
        Inj_IndValid       : in    std_logic                                          := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_ni is

    signal TcReqValue  : std_logic_vector(5 downto 0);
    signal TcReqValid  : std_logic;
    signal IntReqIid   : std_logic_vector(4 downto 0);
    signal IntReqValid : std_logic;
    signal AckReqIid   : std_logic_vector(4 downto 0);
    signal AckReqValid : std_logic;
    signal TxTcValue   : std_logic_vector(5 downto 0);
    signal TxTcValid   : std_logic;
    signal TxTcGrant   : std_logic;
    signal TxIntIid    : std_logic_vector(4 downto 0);
    signal TxIntValid  : std_logic;
    signal TxIntGrant  : std_logic;
    signal TxAckIid    : std_logic_vector(4 downto 0);
    signal TxAckValid  : std_logic;
    signal TxAckGrant  : std_logic;
    signal RxTcValue   : std_logic_vector(5 downto 0);
    signal RxTcValid   : std_logic;
    signal RxIntIid    : std_logic_vector(4 downto 0);
    signal RxIntValid  : std_logic;
    signal RxAckIid    : std_logic_vector(4 downto 0);
    signal RxAckValid  : std_logic;
    signal IndTcValue  : std_logic_vector(5 downto 0);
    signal IndTcValid  : std_logic;
    signal IndIntIid   : std_logic_vector(4 downto 0);
    signal IndIntValid : std_logic;
    signal IndAckIid   : std_logic_vector(4 downto 0);
    signal IndAckValid : std_logic;
    signal BcIgnored   : std_logic;
    signal AckIgnored  : std_logic;

begin

    -- NI-4 broadcast code service
    i_bc : entity work.owr_ni_bc
        generic map (
            TimeCodes_g  => TimeCodes_g,
            Interrupts_g => Interrupts_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            UserClk        => UserClk,
            UserRst        => UserRst,
            S_Tc_TData     => S_Tc_TData,
            S_Tc_TValid    => S_Tc_TValid,
            S_Tc_TReady    => S_Tc_TReady,
            S_Int_TData    => S_Int_TData,
            S_Int_TValid   => S_Int_TValid,
            S_Int_TReady   => S_Int_TReady,
            S_Ack_TData    => S_Ack_TData,
            S_Ack_TValid   => S_Ack_TValid,
            S_Ack_TReady   => S_Ack_TReady,
            M_Tc_TData     => M_Tc_TData,
            M_Tc_TValid    => M_Tc_TValid,
            M_Tc_TReady    => M_Tc_TReady,
            M_Int_TData    => M_Int_TData,
            M_Int_TValid   => M_Int_TValid,
            M_Int_TReady   => M_Int_TReady,
            M_Ack_TData    => M_Ack_TData,
            M_Ack_TValid   => M_Ack_TValid,
            M_Ack_TReady   => M_Ack_TReady,
            Mib_TcValid    => Mib_TcValid,
            Mib_TcValue    => Mib_TcValue,
            Mib_IntValid   => Mib_IntValid,
            Mib_IntIid     => Mib_IntIid,
            Mib_AckValid   => Mib_AckValid,
            Mib_AckIid     => Mib_AckIid,
            TcReq_Value    => TcReqValue,
            TcReq_Valid    => TcReqValid,
            IntReq_Iid     => IntReqIid,
            IntReq_Valid   => IntReqValid,
            AckReq_Iid     => AckReqIid,
            AckReq_Valid   => AckReqValid,
            TxTc_Value     => TxTcValue,
            TxTc_Valid     => TxTcValid,
            TxTc_Grant     => TxTcGrant,
            TxInt_Iid      => TxIntIid,
            TxInt_Valid    => TxIntValid,
            TxInt_Grant    => TxIntGrant,
            TxAck_Iid      => TxAckIid,
            TxAck_Valid    => TxAckValid,
            TxAck_Grant    => TxAckGrant,
            RxTc_Value     => RxTcValue,
            RxTc_Valid     => RxTcValid,
            RxInt_Iid      => RxIntIid,
            RxInt_Valid    => RxIntValid,
            RxAck_Iid      => RxAckIid,
            RxAck_Valid    => RxAckValid,
            IndTc_Value    => IndTcValue,
            IndTc_Valid    => IndTcValid,
            IndInt_Iid     => IndIntIid,
            IndInt_Valid   => IndIntValid,
            IndAck_Iid     => IndAckIid,
            IndAck_Valid   => IndAckValid,
            TxBc_Data      => TxBc_Data,
            TxBc_Valid     => TxBc_Valid,
            TxBc_Ready     => TxBc_Ready,
            RxBc_Data      => RxBc_Data,
            RxBc_Valid     => RxBc_Valid,
            Ev_BcIgnored   => BcIgnored,
            Ev_IndOverflow => Ev_IndOverflow,
            Ecc_ReqSec     => Ecc_ReqSec,
            Ecc_ReqDed     => Ecc_ReqDed,
            Ecc_IndSec     => Ecc_IndSec,
            Ecc_IndDed     => Ecc_IndDed,
            Inj_ReqBitFlip => Inj_ReqBitFlip,
            Inj_ReqValid   => Inj_ReqValid,
            Inj_IndBitFlip => Inj_IndBitFlip,
            Inj_IndValid   => Inj_IndValid
        );

    Ev_BcIgnored <= BcIgnored or AckIgnored;

    -- NI-2 time-code service
    g_tc : if TimeCodes_g generate

        i_tc : entity work.owr_ni_tc
            port map (
                Clk           => Clk,
                Rst           => Rst,
                Cfg_PortReset => Cfg_PortReset,
                Req_Value     => TcReqValue,
                Req_Valid     => TcReqValid,
                Tx_Value      => TxTcValue,
                Tx_Valid      => TxTcValid,
                Tx_Grant      => TxTcGrant,
                Rx_Value      => RxTcValue,
                Rx_Valid      => RxTcValid,
                Ind_Value     => IndTcValue,
                Ind_Valid     => IndTcValid,
                Stat_Register => Stat_TimeCode,
                Ev_Invalid    => Ev_TcInvalid
            );

    end generate;

    g_no_tc : if not TimeCodes_g generate
        -- ECSS 5.6.4.1b: time-codes ignored, requests discarded
        TxTcValue     <= (others => '0');
        TxTcValid     <= '0';
        IndTcValue    <= (others => '0');
        IndTcValid    <= '0';
        Stat_TimeCode <= (others => '0');
        Ev_TcInvalid  <= '0';
    end generate;

    Ev_TcValid <= IndTcValid;

    -- NI-3 distributed interrupt service
    g_int : if Interrupts_g generate

        i_int : entity work.owr_ni_int
            generic map (
                TimerWidth_g => IntTimerWidth_g
            )
            port map (
                Clk                => Clk,
                Rst                => Rst,
                Cfg_PortReset      => Cfg_PortReset,
                Cfg_AckMode        => Cfg_AckMode,
                Cfg_Tick           => Cfg_IntTick,
                Cfg_Holdoff        => Cfg_IntHoldoff,
                Cfg_AckDelay       => Cfg_AckDelay,
                IntReq_Iid         => IntReqIid,
                IntReq_Valid       => IntReqValid,
                AckReq_Iid         => AckReqIid,
                AckReq_Valid       => AckReqValid,
                TxInt_Iid          => TxIntIid,
                TxInt_Valid        => TxIntValid,
                TxInt_Grant        => TxIntGrant,
                TxAck_Iid          => TxAckIid,
                TxAck_Valid        => TxAckValid,
                TxAck_Grant        => TxAckGrant,
                Tx_Discarded       => TxBc_Discarded,
                RxInt_Iid          => RxIntIid,
                RxInt_Valid        => RxIntValid,
                RxAck_Iid          => RxAckIid,
                RxAck_Valid        => RxAckValid,
                IndInt_Iid         => IndIntIid,
                IndInt_Valid       => IndIntValid,
                IndAck_Iid         => IndAckIid,
                IndAck_Valid       => IndAckValid,
                Stat_Active        => Stat_IntActive,
                Ev_IntReqDiscarded => Ev_IntReqDiscarded,
                Ev_AckReqDiscarded => Ev_AckReqDiscarded,
                Ev_AckIgnored      => AckIgnored
            );

    end generate;

    g_no_int : if not Interrupts_g generate
        -- ECSS 5.6.5.1b: interrupt codes ignored, requests discarded
        TxIntIid           <= (others => '0');
        TxIntValid         <= '0';
        TxAckIid           <= (others => '0');
        TxAckValid         <= '0';
        IndIntIid          <= (others => '0');
        IndIntValid        <= '0';
        IndAckIid          <= (others => '0');
        IndAckValid        <= '0';
        Stat_IntActive     <= (others => '0');
        Ev_IntReqDiscarded <= IntReqValid;
        Ev_AckReqDiscarded <= AckReqValid;
        AckIgnored         <= '0';
    end generate;

    Ev_IntRx    <= IndIntValid;
    Ev_AckRx    <= IndAckValid;
    Ev_AckRxIid <= IndAckIid;

end architecture;
