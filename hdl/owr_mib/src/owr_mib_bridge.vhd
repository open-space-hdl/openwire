---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Register bridge of the OpenWire MIB (MG-2): AXI4-Lite slave in MgmtClk; every register access
-- crosses to the register file in LinkClk through an FT FIFO, read data returns through a second one.
-- Accesses are executed in order, so a read returns the value after all earlier writes.
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

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_mib_bridge is
    generic (
        ReadTimeoutClks_g : positive := 1000;
        ReqDepth_g        : positive := 16
    );
    port (
        -- Management clock domain: AXI4-Lite
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
        -- Link clock domain: register bus of the register file
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        Rb_Addr           : out   std_logic_vector(7 downto 0);
        Rb_Wr             : out   std_logic;
        Rb_ByteEna        : out   std_logic_vector(3 downto 0);
        Rb_WrData         : out   std_logic_vector(31 downto 0);
        Rb_Rd             : out   std_logic;
        Rb_RdData         : in    std_logic_vector(31 downto 0);
        Rb_RdValid        : in    std_logic;
        -- EDAC of the FIFOs
        Ecc_ReqSec        : out   std_logic; -- Clk
        Ecc_ReqDed        : out   std_logic; -- Clk
        Ecc_RspSec        : out   std_logic; -- MgmtClk
        Ecc_RspDed        : out   std_logic; -- MgmtClk
        Inj_ReqBitFlip    : in    std_logic_vector(eccCodewordWidth(45) - 1 downto 0) := (others => '0'); -- MgmtClk
        Inj_ReqValid      : in    std_logic                                           := '0';               -- MgmtClk
        Inj_RspBitFlip    : in    std_logic_vector(eccCodewordWidth(34) - 1 downto 0) := (others => '0'); -- Clk
        Inj_RspValid      : in    std_logic                                           := '0'                -- Clk
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_mib_bridge is

    -- Request: tag (44:43), read (42), word address (41:36), byte enables (35:32), data (31:0)
    -- Response: tag (33:32), data (31:0)
    constant ReqWidth_c : positive := 45;
    constant RspWidth_c : positive := 34;

    -- Management side
    signal ArValid    : std_logic;
    signal ArReady    : std_logic;
    signal AwValid    : std_logic;
    signal AwReady    : std_logic;
    signal WValid     : std_logic;
    signal WReady     : std_logic;
    signal Room       : std_logic;
    signal MAddr      : std_logic_vector(7 downto 0);
    signal MWr        : std_logic;
    signal MByteEna   : std_logic_vector(3 downto 0);
    signal MWrData    : std_logic_vector(31 downto 0);
    signal MRd        : std_logic;
    signal MRdData    : std_logic_vector(31 downto 0);
    signal MRdValid   : std_logic;
    signal Tag        : unsigned(1 downto 0);
    signal ReqIn      : std_logic_vector(ReqWidth_c - 1 downto 0);
    signal ReqInVld   : std_logic;
    signal ReqAlmFull : std_logic;
    signal RspOut     : std_logic_vector(RspWidth_c - 1 downto 0);
    signal RspValid   : std_logic;
    signal RspSec     : std_logic;
    signal RspDed     : std_logic;
    -- Link side
    signal ReqOut     : std_logic_vector(ReqWidth_c - 1 downto 0);
    signal ReqValid   : std_logic;
    signal ReqSec     : std_logic;
    signal ReqDed     : std_logic;
    signal LastTag    : std_logic_vector(1 downto 0);
    signal RspIn      : std_logic_vector(RspWidth_c - 1 downto 0);

begin

    -----------------------------------------------------------------------------------------------
    -- Management side
    -----------------------------------------------------------------------------------------------
    -- New accesses are only accepted while the request FIFO has room
    ArValid           <= S_AxiLite_ArValid and Room;
    S_AxiLite_ArReady <= ArReady and Room;
    AwValid           <= S_AxiLite_AwValid and Room;
    S_AxiLite_AwReady <= AwReady and Room;
    WValid            <= S_AxiLite_WValid and Room;
    S_AxiLite_WReady  <= WReady and Room;
    Room              <= not ReqAlmFull;

    i_axi : entity olo.olo_axi_lite_slave
        generic map (
            AxiAddrWidth_g    => 8,
            AxiDataWidth_g    => 32,
            ReadTimeoutClks_g => ReadTimeoutClks_g
        )
        port map (
            Clk               => MgmtClk,
            Rst               => MgmtRst,
            S_AxiLite_ArAddr  => S_AxiLite_ArAddr,
            S_AxiLite_ArValid => ArValid,
            S_AxiLite_ArReady => ArReady,
            S_AxiLite_AwAddr  => S_AxiLite_AwAddr,
            S_AxiLite_AwValid => AwValid,
            S_AxiLite_AwReady => AwReady,
            S_AxiLite_WData   => S_AxiLite_WData,
            S_AxiLite_WStrb   => S_AxiLite_WStrb,
            S_AxiLite_WValid  => WValid,
            S_AxiLite_WReady  => WReady,
            S_AxiLite_BResp   => S_AxiLite_BResp,
            S_AxiLite_BValid  => S_AxiLite_BValid,
            S_AxiLite_BReady  => S_AxiLite_BReady,
            S_AxiLite_RData   => S_AxiLite_RData,
            S_AxiLite_RResp   => S_AxiLite_RResp,
            S_AxiLite_RValid  => S_AxiLite_RValid,
            S_AxiLite_RReady  => S_AxiLite_RReady,
            Rb_Addr           => MAddr,
            Rb_Wr             => MWr,
            Rb_ByteEna        => MByteEna,
            Rb_WrData         => MWrData,
            Rb_Rd             => MRd,
            Rb_RdData         => MRdData,
            Rb_RdValid        => MRdValid
        );

    -- Every read gets a new tag; only the response with the tag of the last read is passed
    p_tag : process (MgmtClk) is
    begin
        if rising_edge(MgmtClk) then
            if MRd = '1' then
                Tag <= Tag + 1;
            end if;
            if MgmtRst = '1' then
                Tag <= (others => '0');
            end if;
        end if;
    end process;

    -- A read carries no data (the write data register of the slave is not defined before the first write)
    ReqIn    <= std_logic_vector(Tag + 1) & '1' & MAddr(7 downto 2) & "0000" & x"00000000" when MRd = '1' else
                std_logic_vector(Tag) & '0' & MAddr(7 downto 2) & MByteEna & MWrData;
    ReqInVld <= MWr or MRd;

    i_req : entity olo.olo_ft_fifo_async
        generic map (
            Width_g         => ReqWidth_c,
            Depth_g         => ReqDepth_g,
            AlmFullOn_g     => true,
            AlmFullLevel_g  => ReqDepth_g - 2,
            ReadyRstState_g => '0'
        )
        port map (
            In_Clk            => MgmtClk,
            In_Rst            => MgmtRst,
            In_Data           => ReqIn,
            In_Valid          => ReqInVld,
            In_AlmFull        => ReqAlmFull,
            Out_Clk           => Clk,
            Out_Rst           => Rst,
            Out_Data          => ReqOut,
            Out_Valid         => ReqValid,
            Out_Ready         => '1',
            Out_EccSec        => ReqSec,
            Out_EccDed        => ReqDed,
            In_ErrInj_BitFlip => Inj_ReqBitFlip,
            In_ErrInj_Valid   => Inj_ReqValid
        );

    -----------------------------------------------------------------------------------------------
    -- Link side: one access per cycle, a request with a double error is dropped (a read then times out)
    -----------------------------------------------------------------------------------------------
    Rb_Addr    <= ReqOut(41 downto 36) & "00";
    Rb_ByteEna <= ReqOut(35 downto 32);
    Rb_WrData  <= ReqOut(31 downto 0);
    Rb_Wr      <= ReqValid and not ReqOut(42) and not ReqDed;
    Rb_Rd      <= ReqValid and ReqOut(42) and not ReqDed;
    Ecc_ReqSec <= ReqValid and ReqSec;
    Ecc_ReqDed <= ReqValid and ReqDed;

    p_lasttag : process (Clk) is
    begin
        if rising_edge(Clk) then
            if ReqValid = '1' and ReqOut(42) = '1' then
                LastTag <= ReqOut(44 downto 43);
            end if;
            if Rst = '1' then
                LastTag <= (others => '0');
            end if;
        end if;
    end process;

    RspIn <= LastTag & Rb_RdData;

    i_rsp : entity olo.olo_ft_fifo_async
        generic map (
            Width_g         => RspWidth_c,
            Depth_g         => 4,
            ReadyRstState_g => '0'
        )
        port map (
            In_Clk            => Clk,
            In_Rst            => Rst,
            In_Data           => RspIn,
            In_Valid          => Rb_RdValid,
            Out_Clk           => MgmtClk,
            Out_Rst           => MgmtRst,
            Out_Data          => RspOut,
            Out_Valid         => RspValid,
            Out_Ready         => '1',
            Out_EccSec        => RspSec,
            Out_EccDed        => RspDed,
            In_ErrInj_BitFlip => Inj_RspBitFlip,
            In_ErrInj_Valid   => Inj_RspValid
        );

    -- A response with a double error or a tag of an earlier read is dropped
    MRdData    <= RspOut(31 downto 0);
    MRdValid   <= RspValid when RspDed = '0' and RspOut(33 downto 32) = std_logic_vector(Tag) else '0';
    Ecc_RspSec <= RspValid and RspSec;
    Ecc_RspDed <= RspValid and RspDed;

end architecture;
