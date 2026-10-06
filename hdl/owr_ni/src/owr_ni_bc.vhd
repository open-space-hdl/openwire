---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Broadcast code service of a SpaceWire node (NI-4): request and indication FIFOs between the user
-- ports (UserClk) and the Network layer (LinkClk), priority of the codes passed to the Data Link
-- layer and decoding of the received codes (ECSS-E-ST-50-12C Rev.1 clause 5.6.3).
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
entity owr_ni_bc is
    generic (
        TimeCodes_g  : boolean  := true;
        Interrupts_g : boolean  := true;
        ReqDepth_g   : positive := 8;
        IndDepth_g   : positive := 16
    );
    port (
        -- Link clock domain
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- User clock domain
        UserClk        : in    std_logic;
        UserRst        : in    std_logic;
        -- User requests (UserClk)
        S_Tc_TData     : in    std_logic_vector(5 downto 0);
        S_Tc_TValid    : in    std_logic;
        S_Tc_TReady    : out   std_logic;
        S_Int_TData    : in    std_logic_vector(4 downto 0);
        S_Int_TValid   : in    std_logic;
        S_Int_TReady   : out   std_logic;
        S_Ack_TData    : in    std_logic_vector(4 downto 0);
        S_Ack_TValid   : in    std_logic;
        S_Ack_TReady   : out   std_logic;
        -- User indications (UserClk)
        M_Tc_TData     : out   std_logic_vector(5 downto 0);
        M_Tc_TValid    : out   std_logic;
        M_Tc_TReady    : in    std_logic;
        M_Int_TData    : out   std_logic_vector(4 downto 0);
        M_Int_TValid   : out   std_logic;
        M_Int_TReady   : in    std_logic;
        M_Ack_TData    : out   std_logic_vector(4 downto 0);
        M_Ack_TValid   : out   std_logic;
        M_Ack_TReady   : in    std_logic;
        -- Requests of the MIB (one-cycle pulses)
        Mib_TcValid    : in    std_logic;
        Mib_TcValue    : in    std_logic_vector(5 downto 0);
        Mib_IntValid   : in    std_logic;
        Mib_IntIid     : in    std_logic_vector(4 downto 0);
        Mib_AckValid   : in    std_logic;
        Mib_AckIid     : in    std_logic_vector(4 downto 0);
        -- Requests to the services
        TcReq_Value    : out   std_logic_vector(5 downto 0);
        TcReq_Valid    : out   std_logic;
        IntReq_Iid     : out   std_logic_vector(4 downto 0);
        IntReq_Valid   : out   std_logic;
        AckReq_Iid     : out   std_logic_vector(4 downto 0);
        AckReq_Valid   : out   std_logic;
        -- Codes to send of the services
        TxTc_Value     : in    std_logic_vector(5 downto 0);
        TxTc_Valid     : in    std_logic;
        TxTc_Grant     : out   std_logic;
        TxInt_Iid      : in    std_logic_vector(4 downto 0);
        TxInt_Valid    : in    std_logic;
        TxInt_Grant    : out   std_logic;
        TxAck_Iid      : in    std_logic_vector(4 downto 0);
        TxAck_Valid    : in    std_logic;
        TxAck_Grant    : out   std_logic;
        -- Received codes to the services
        RxTc_Value     : out   std_logic_vector(5 downto 0);
        RxTc_Valid     : out   std_logic;
        RxInt_Iid      : out   std_logic_vector(4 downto 0);
        RxInt_Valid    : out   std_logic;
        RxAck_Iid      : out   std_logic_vector(4 downto 0);
        RxAck_Valid    : out   std_logic;
        -- Indications of the services
        IndTc_Value    : in    std_logic_vector(5 downto 0);
        IndTc_Valid    : in    std_logic;
        IndInt_Iid     : in    std_logic_vector(4 downto 0);
        IndInt_Valid   : in    std_logic;
        IndAck_Iid     : in    std_logic_vector(4 downto 0);
        IndAck_Valid   : in    std_logic;
        -- Data Link layer
        TxBc_Data      : out   std_logic_vector(7 downto 0);
        TxBc_Valid     : out   std_logic;
        TxBc_Ready     : in    std_logic;
        RxBc_Data      : in    std_logic_vector(7 downto 0);
        RxBc_Valid     : in    std_logic;
        -- Events
        Ev_BcIgnored   : out   std_logic;
        Ev_IndOverflow : out   std_logic;
        -- EDAC of the FIFOs
        Ecc_ReqSec     : out   std_logic;
        Ecc_ReqDed     : out   std_logic;
        Ecc_IndSec     : out   std_logic; -- UserClk
        Ecc_IndDed     : out   std_logic; -- UserClk
        Inj_ReqBitFlip : in    std_logic_vector(eccCodewordWidth(8) - 1 downto 0) := (others => '0'); -- UserClk
        Inj_ReqValid   : in    std_logic                                          := '0';               -- UserClk
        Inj_IndBitFlip : in    std_logic_vector(eccCodewordWidth(8) - 1 downto 0) := (others => '0');
        Inj_IndValid   : in    std_logic                                          := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_ni_bc is

    -- User side of the request FIFO
    signal UReq      : std_logic_vector(2 downto 0);
    signal UGrant    : std_logic_vector(2 downto 0);
    signal ReqInData : BcEntry_t;
    signal ReqInVld  : std_logic;
    signal ReqInRdy  : std_logic;
    -- Link side of the request FIFO
    signal ReqData   : BcEntry_t;
    signal ReqValid  : std_logic;
    signal ReqReady  : std_logic;
    signal ReqSec    : std_logic;
    signal ReqDed    : std_logic;
    -- Indication FIFO
    signal IndInData : BcEntry_t;
    signal IndInVld  : std_logic;
    signal IndInRdy  : std_logic;
    signal IndData   : BcEntry_t;
    signal IndValid  : std_logic;
    signal IndReady  : std_logic;
    signal IndSec    : std_logic;
    signal IndDed    : std_logic;
    -- Received codes
    signal RxType    : BcType_t;
    signal RxTcVld   : std_logic;
    signal RxIntVld  : std_logic;
    signal RxAckVld  : std_logic;
    signal Ignored   : std_logic;
    signal IndOvf    : std_logic;

begin

    -----------------------------------------------------------------------------------------------
    -- Requests: priority time-code, acknowledgement, interrupt on the user side, then one FIFO
    -----------------------------------------------------------------------------------------------
    UReq <= S_Tc_TValid & S_Ack_TValid & S_Int_TValid;

    i_req_arb : entity olo.olo_base_arb_prio
        generic map (
            Width_g   => 3,
            Latency_g => 0
        )
        port map (
            Clk       => UserClk,
            Rst       => UserRst,
            In_Req    => UReq,
            Out_Grant => UGrant
        );

    ReqInVld  <= '1' when UReq /= "000" else '0';
    ReqInData <= BcKindTimeCode_c & S_Tc_TData when UGrant(2) = '1' else
                 BcKindAck_c & '0' & S_Ack_TData when UGrant(1) = '1' else
                 BcKindInterrupt_c & '0' & S_Int_TData;

    S_Tc_TReady  <= UGrant(2) and ReqInRdy;
    S_Ack_TReady <= UGrant(1) and ReqInRdy;
    S_Int_TReady <= UGrant(0) and ReqInRdy;

    i_req_fifo : entity olo.olo_ft_fifo_async
        generic map (
            Width_g         => 8,
            Depth_g         => ReqDepth_g,
            ReadyRstState_g => '0'
        )
        port map (
            In_Clk            => UserClk,
            In_Rst            => UserRst,
            In_Data           => ReqInData,
            In_Valid          => ReqInVld,
            In_Ready          => ReqInRdy,
            Out_Clk           => Clk,
            Out_Rst           => Rst,
            Out_Data          => ReqData,
            Out_Valid         => ReqValid,
            Out_Ready         => ReqReady,
            Out_EccSec        => ReqSec,
            Out_EccDed        => ReqDed,
            In_ErrInj_BitFlip => Inj_ReqBitFlip,
            In_ErrInj_Valid   => Inj_ReqValid
        );

    Ecc_ReqSec <= ReqSec and ReqValid and ReqReady;
    Ecc_ReqDed <= ReqDed and ReqValid and ReqReady;

    -- A request of the MIB has precedence over the FIFO in the same cycle; a request with a double error is
    -- discarded
    p_req : process (all) is
        variable FifoReq_v : boolean;
        variable Kind_v    : BcKind_t;
    begin
        ReqReady  <= not (Mib_TcValid or Mib_IntValid or Mib_AckValid);
        FifoReq_v := ReqValid = '1' and ReqReady = '1' and ReqDed = '0';
        Kind_v    := ReqData(7 downto 6);

        TcReq_Value  <= ReqData(5 downto 0);
        IntReq_Iid   <= ReqData(4 downto 0);
        AckReq_Iid   <= ReqData(4 downto 0);
        TcReq_Valid  <= '1' when FifoReq_v and Kind_v = BcKindTimeCode_c else '0';
        IntReq_Valid <= '1' when FifoReq_v and Kind_v = BcKindInterrupt_c else '0';
        AckReq_Valid <= '1' when FifoReq_v and Kind_v = BcKindAck_c else '0';

        if Mib_TcValid = '1' then
            TcReq_Value <= Mib_TcValue;
            TcReq_Valid <= '1';
        end if;
        if Mib_IntValid = '1' then
            IntReq_Iid   <= Mib_IntIid;
            IntReq_Valid <= '1';
        end if;
        if Mib_AckValid = '1' then
            AckReq_Iid   <= Mib_AckIid;
            AckReq_Valid <= '1';
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Codes to send (ECSS 5.6.3d): time-code, then acknowledgement code, then interrupt code
    -----------------------------------------------------------------------------------------------
    p_tx : process (all) is
    begin
        TxTc_Grant  <= '0';
        TxAck_Grant <= '0';
        TxInt_Grant <= '0';
        TxBc_Valid  <= TxTc_Valid or TxAck_Valid or TxInt_Valid;
        if TxTc_Valid = '1' then
            TxBc_Data  <= BcTypeTimeCode_c & TxTc_Value;
            TxTc_Grant <= TxBc_Ready;
        elsif TxAck_Valid = '1' then
            TxBc_Data   <= BcTypeInterrupt_c & '1' & TxAck_Iid;
            TxAck_Grant <= TxBc_Ready;
        else
            TxBc_Data   <= BcTypeInterrupt_c & '0' & TxInt_Iid;
            TxInt_Grant <= TxBc_Ready and TxInt_Valid;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Received codes (ECSS 5.6.3a, b, f): decoded by type, unknown types and disabled services ignored
    -----------------------------------------------------------------------------------------------
    RxType <= RxBc_Data(7 downto 6);

    RxTcVld  <= RxBc_Valid when RxType = BcTypeTimeCode_c and TimeCodes_g else '0';
    RxIntVld <= RxBc_Valid when RxType = BcTypeInterrupt_c and RxBc_Data(BcAckIdx_c) = '0' and Interrupts_g else '0';
    RxAckVld <= RxBc_Valid when RxType = BcTypeInterrupt_c and RxBc_Data(BcAckIdx_c) = '1' and Interrupts_g else '0';
    Ignored  <= RxBc_Valid and not (RxTcVld or RxIntVld or RxAckVld);

    RxTc_Value  <= RxBc_Data(5 downto 0);
    RxTc_Valid  <= RxTcVld;
    RxInt_Iid   <= RxBc_Data(4 downto 0);
    RxInt_Valid <= RxIntVld;
    RxAck_Iid   <= RxBc_Data(4 downto 0);
    RxAck_Valid <= RxAckVld;

    -----------------------------------------------------------------------------------------------
    -- Indications: one FIFO, then one port per service on the user side
    -----------------------------------------------------------------------------------------------
    IndInVld  <= IndTc_Valid or IndInt_Valid or IndAck_Valid;
    IndInData <= BcKindTimeCode_c & IndTc_Value when IndTc_Valid = '1' else
                 BcKindInterrupt_c & '0' & IndInt_Iid when IndInt_Valid = '1' else
                 BcKindAck_c & '0' & IndAck_Iid;

    i_ind_fifo : entity olo.olo_ft_fifo_async
        generic map (
            Width_g         => 8,
            Depth_g         => IndDepth_g,
            ReadyRstState_g => '0'
        )
        port map (
            In_Clk            => Clk,
            In_Rst            => Rst,
            In_Data           => IndInData,
            In_Valid          => IndInVld,
            In_Ready          => IndInRdy,
            Out_Clk           => UserClk,
            Out_Rst           => UserRst,
            Out_Data          => IndData,
            Out_Valid         => IndValid,
            Out_Ready         => IndReady,
            Out_EccSec        => IndSec,
            Out_EccDed        => IndDed,
            In_ErrInj_BitFlip => Inj_IndBitFlip,
            In_ErrInj_Valid   => Inj_IndValid
        );

    IndOvf <= IndInVld and not IndInRdy;

    Ecc_IndSec <= IndSec and IndValid and IndReady;
    Ecc_IndDed <= IndDed and IndValid and IndReady;

    -- Demultiplexer of the indications; an indication with a double error is discarded
    p_ind : process (all) is
        variable Kind_v : BcKind_t;
    begin
        Kind_v       := IndData(7 downto 6);
        M_Tc_TData   <= IndData(5 downto 0);
        M_Int_TData  <= IndData(4 downto 0);
        M_Ack_TData  <= IndData(4 downto 0);
        M_Tc_TValid  <= '0';
        M_Int_TValid <= '0';
        M_Ack_TValid <= '0';
        if IndDed = '1' then
            IndReady <= '1';
        elsif Kind_v = BcKindTimeCode_c then
            M_Tc_TValid <= IndValid;
            IndReady    <= M_Tc_TReady;
        elsif Kind_v = BcKindInterrupt_c then
            M_Int_TValid <= IndValid;
            IndReady     <= M_Int_TReady;
        else
            M_Ack_TValid <= IndValid;
            IndReady     <= M_Ack_TReady;
        end if;
    end process;

    -- Events
    p_ev : process (Clk) is
    begin
        if rising_edge(Clk) then
            Ev_BcIgnored   <= Ignored;
            Ev_IndOverflow <= IndOvf;
            if Rst = '1' then
                Ev_BcIgnored   <= '0';
                Ev_IndOverflow <= '0';
            end if;
        end if;
    end process;

end architecture;
