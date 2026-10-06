---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- One node of the core testbench: owr_core with its own clocks, AXI4-Stream VVCs on the packet
-- ports, an AXI4-Lite VVC on the MIB and a log of the broadcast service indications.
--
-- Documentation: hdl/owr_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.owr_tb_ds_pkg.all;
    use work.owr_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_core_tb_node is
    generic (
        LinkHalf_g  : time;
        UserHalf_g  : time;
        MgmtHalf_g  : time;
        LinkFreq_g  : real;
        Services_g  : boolean := true;
        TxVvc_g     : natural;
        RxVvc_g     : natural;
        AxiVvc_g    : natural;
        IndLog_g    : natural
    );
    port (
        Rst      : in    std_logic;
        BcIn     : in    CoreBcIn_t;
        Obs      : out   CoreObs_t;
        UserClk  : out   std_logic;
        LinkClk  : out   std_logic;
        Spw_DOut : out   std_logic;
        Spw_SOut : out   std_logic;
        Spw_DIn  : in    std_logic;
        Spw_SIn  : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_core_tb_node is

    signal UserClk_i : std_logic := '0';
    signal LinkClk_i : std_logic := '0';
    signal MgmtClk_i : std_logic := '0';
    signal TxData    : std_logic_vector(7 downto 0);
    signal TxLast    : std_logic;
    signal TxValid   : std_logic;
    signal TxReady   : std_logic;
    signal RxData    : std_logic_vector(7 downto 0);
    signal RxLast    : std_logic;
    signal RxValid   : std_logic;
    signal RxReady   : std_logic;
    signal TcData    : std_logic_vector(5 downto 0);
    signal TcValid   : std_logic;
    signal IntData   : std_logic_vector(4 downto 0);
    signal IntValid  : std_logic;
    signal AckData   : std_logic_vector(4 downto 0);
    signal AckValid  : std_logic;
    signal ArAddr    : std_logic_vector(7 downto 0);
    signal ArValid   : std_logic;
    signal ArReady   : std_logic;
    signal AwAddr    : std_logic_vector(7 downto 0);
    signal AwValid   : std_logic;
    signal AwReady   : std_logic;
    signal WData     : std_logic_vector(31 downto 0);
    signal WStrb     : std_logic_vector(3 downto 0);
    signal WValid    : std_logic;
    signal WReady    : std_logic;
    signal BResp     : std_logic_vector(1 downto 0);
    signal BValid    : std_logic;
    signal BReady    : std_logic;
    signal RData     : std_logic_vector(31 downto 0);
    signal RResp     : std_logic_vector(1 downto 0);
    signal RValid    : std_logic;
    signal RReady    : std_logic;

begin

    UserClk_i <= not UserClk_i after UserHalf_g;
    LinkClk_i <= not LinkClk_i after LinkHalf_g;
    MgmtClk_i <= not MgmtClk_i after MgmtHalf_g;
    UserClk   <= UserClk_i;
    LinkClk   <= LinkClk_i;

    i_core : entity work.owr_core
        generic map (
            LinkClkFreq_g => LinkFreq_g,
            TimeCodes_g   => Services_g,
            Interrupts_g  => Services_g
        )
        port map (
            Rst               => Rst,
            UserClk           => UserClk_i,
            LinkClk           => LinkClk_i,
            MgmtClk           => MgmtClk_i,
            S_Pkt_TData       => TxData,
            S_Pkt_TLast       => TxLast,
            S_Pkt_TValid      => TxValid,
            S_Pkt_TReady      => TxReady,
            M_Pkt_TData       => RxData,
            M_Pkt_TLast       => RxLast,
            M_Pkt_TValid      => RxValid,
            M_Pkt_TReady      => RxReady,
            S_Tc_TData        => BcIn.TcData,
            S_Tc_TValid       => BcIn.TcValid,
            S_Tc_TReady       => Obs.TcReady,
            M_Tc_TData        => TcData,
            M_Tc_TValid       => TcValid,
            M_Tc_TReady       => '1',
            S_Int_TData       => BcIn.IntData,
            S_Int_TValid      => BcIn.IntValid,
            S_Int_TReady      => Obs.IntReady,
            S_IntAck_TData    => BcIn.AckData,
            S_IntAck_TValid   => BcIn.AckValid,
            S_IntAck_TReady   => Obs.AckReady,
            M_Int_TData       => IntData,
            M_Int_TValid      => IntValid,
            M_Int_TReady      => '1',
            M_IntAck_TData    => AckData,
            M_IntAck_TValid   => AckValid,
            M_IntAck_TReady   => '1',
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
            Irq               => Obs.Irq,
            Spw_DOut          => Spw_DOut,
            Spw_SOut          => Spw_SOut,
            Spw_DIn           => Spw_DIn,
            Spw_SIn           => Spw_SIn,
            Phy_TxEn          => Obs.PhyTxEn,
            Phy_RxEn          => Obs.PhyRxEn
        );

    i_tx_vvc : entity work.owr_tb_axis_master
        generic map (
            InstanceIdx_g => TxVvc_g,
            DataWidth_g   => 8
        )
        port map (
            Clk       => UserClk_i,
            Out_Data  => TxData,
            Out_Last  => TxLast,
            Out_Valid => TxValid,
            Out_Ready => TxReady
        );

    i_rx_vvc : entity work.owr_tb_axis_slave
        generic map (
            InstanceIdx_g => RxVvc_g,
            DataWidth_g   => 8
        )
        port map (
            Clk      => UserClk_i,
            In_Data  => RxData,
            In_Last  => RxLast,
            In_Valid => RxValid,
            In_Ready => RxReady
        );

    i_axi : entity work.owr_tb_axilite_master
        generic map (
            InstanceIdx_g => AxiVvc_g,
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

    -- Log of the indications: kind (7:6) and value
    p_log : process (UserClk_i) is
        variable Char_v : TbChar_t;
    begin
        if rising_edge(UserClk_i) and Rst = '0' then
            Char_v      := TbCharInit_c;
            Char_v.Kind := TbBc;
            Char_v.T    := now;
            if TcValid = '1' then
                Char_v.Data := "00" & TcData;
                FarEnd_v.rxPush(IndLog_g, Char_v);
            end if;
            if IntValid = '1' then
                Char_v.Data := "010" & IntData;
                FarEnd_v.rxPush(IndLog_g, Char_v);
            end if;
            if AckValid = '1' then
                Char_v.Data := "100" & AckData;
                FarEnd_v.rxPush(IndLog_g, Char_v);
            end if;
        end if;
    end process;

end architecture;
