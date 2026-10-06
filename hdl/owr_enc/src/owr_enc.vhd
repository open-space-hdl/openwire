---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Encoding layer of OpenWire (ECSS-E-ST-50-12C Rev.1 clause 5.4): transmitter (EN-1), receiver
-- (EN-2) and the port loopback (EN-3) that connects the transmitter to the receiver for tests.
--
-- Documentation: hdl/owr_enc/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.owr_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_enc is
    generic (
        ClkFreq_g    : real                  := 100.0e6;
        SyncStages_g : positive range 2 to 4 := 2
    );
    port (
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        -- Control from the link state machine and the MIB
        TxEnable      : in    std_logic;
        RxEnable      : in    std_logic;
        TxRun         : in    std_logic;
        Cfg_RunDiv    : in    std_logic_vector(7 downto 0);
        Cfg_Loopback  : in    std_logic;
        -- Characters to send
        TxChar_Kind   : in    CharKind_t;
        TxChar_Data   : in    std_logic_vector(7 downto 0);
        TxChar_Ack    : out   std_logic;
        -- Received characters and status
        RxChar_Valid  : out   std_logic;
        RxChar_Kind   : out   CharKind_t;
        RxChar_Data   : out   std_logic_vector(7 downto 0);
        Rx_GotNull    : out   std_logic;
        Rx_ParityErr  : out   std_logic;
        Rx_EscErr     : out   std_logic;
        Rx_Disconnect : out   std_logic;
        -- Data and strobe
        Spw_DOut      : out   std_logic;
        Spw_SOut      : out   std_logic;
        Spw_DIn       : in    std_logic;
        Spw_SIn       : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_enc is

    constant InitDiv_c : positive := initDivider(ClkFreq_g);

    -- Disconnect: timer cycles after the synchronised edge; the synchroniser and the edge detector add
    -- SyncStages_g + 1 cycles
    constant DisconnectCycles_c : positive := timeCycles(TimeDisconnect_c, ClkFreq_g) - SyncStages_g - 1;

    signal DOut : std_logic;
    signal SOut : std_logic;
    signal DIn  : std_logic;
    signal SIn  : std_logic;

begin

    -- Initial data signalling rate 10 Mb/s +/- 1 Mb/s (ECSS 5.4.10.1a)
    assert ClkFreq_g / real(InitDiv_c) >= 9.0e6 and ClkFreq_g / real(InitDiv_c) <= 11.0e6
        report "owr_enc: ClkFreq_g does not allow 10 Mb/s +/- 1 Mb/s with an integer divider"
        severity failure;
    -- Disconnect time between 727 ns and 1 us (ECSS 5.4.8c), including one cycle of sampling uncertainty
    assert real(DisconnectCycles_c + SyncStages_g + 1) / ClkFreq_g > 727.0e-9 and
           real(DisconnectCycles_c + SyncStages_g + 2) / ClkFreq_g <= 1.0e-6
        report "owr_enc: ClkFreq_g too low for the disconnect time of 727 ns to 1 us"
        severity failure;

    i_tx : entity work.owr_enc_tx
        generic map (
            InitDiv_g => InitDiv_c
        )
        port map (
            Clk        => Clk,
            Rst        => Rst,
            TxEnable   => TxEnable,
            TxRun      => TxRun,
            Cfg_RunDiv => Cfg_RunDiv,
            Char_Kind  => TxChar_Kind,
            Char_Data  => TxChar_Data,
            Char_Ack   => TxChar_Ack,
            Spw_DOut   => DOut,
            Spw_SOut   => SOut
        );

    Spw_DOut <= DOut;
    Spw_SOut <= SOut;

    -- Port loopback (ECSS 5.6.10f)
    DIn <= DOut when Cfg_Loopback = '1' else Spw_DIn;
    SIn <= SOut when Cfg_Loopback = '1' else Spw_SIn;

    i_rx : entity work.owr_enc_rx
        generic map (
            DisconnectCycles_g => DisconnectCycles_c,
            SyncStages_g       => SyncStages_g
        )
        port map (
            Clk           => Clk,
            Rst           => Rst,
            RxEnable      => RxEnable,
            Spw_DIn       => DIn,
            Spw_SIn       => SIn,
            Char_Valid    => RxChar_Valid,
            Char_Kind     => RxChar_Kind,
            Char_Data     => RxChar_Data,
            Rx_GotNull    => Rx_GotNull,
            Rx_ParityErr  => Rx_ParityErr,
            Rx_EscErr     => Rx_EscErr,
            Rx_Disconnect => Rx_Disconnect
        );

end architecture;
