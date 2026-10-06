---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Data Link layer of OpenWire (ECSS-E-ST-50-12C Rev.1 clause 5.5): transmit and receive FIFOs
-- (DL-1, DL-2), link state machine (DL-3), flow control manager (DL-4), transmit scheduler (DL-5),
-- receive handler (DL-6) and link error recovery (DL-7).
--
-- Documentation: hdl/owr_dl/docs/architecture.md

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
entity owr_dl is
    generic (
        ClkFreq_g     : real     := 100.0e6;
        TxFifoDepth_g : positive := 64;
        RxFifoDepth_g : positive := 64
    );
    port (
        -- Link clock domain
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        -- User clock domain
        UserClk          : in    std_logic;
        UserRst          : in    std_logic;
        -- N-Chars of the user (UserClk)
        TxUser_Data      : in    NChar_t;
        TxUser_Valid     : in    std_logic;
        TxUser_Ready     : out   std_logic;
        RxUser_Data      : out   NChar_t;
        RxUser_Valid     : out   std_logic;
        RxUser_Ready     : in    std_logic;
        -- Broadcast codes of the Network layer
        TxBc_Data        : in    std_logic_vector(7 downto 0);
        TxBc_Valid       : in    std_logic;
        TxBc_Ready       : out   std_logic;
        TxBc_Discarded   : out   std_logic;
        RxBc_Data        : out   std_logic_vector(7 downto 0);
        RxBc_Valid       : out   std_logic;
        -- Encoding layer
        TxEnable         : out   std_logic;
        RxEnable         : out   std_logic;
        TxRun            : out   std_logic;
        TxChar_Kind      : out   CharKind_t;
        TxChar_Data      : out   std_logic_vector(7 downto 0);
        TxChar_Ack       : in    std_logic;
        RxChar_Valid     : in    std_logic;
        RxChar_Kind      : in    CharKind_t;
        RxChar_Data      : in    std_logic_vector(7 downto 0);
        Rx_GotNull       : in    std_logic;
        Rx_ParityErr     : in    std_logic;
        Rx_EscErr        : in    std_logic;
        Rx_Disconnect    : in    std_logic;
        -- Management parameters
        Cfg_PortReset    : in    std_logic;
        Cfg_LinkDisabled : in    std_logic;
        Cfg_LinkStart    : in    std_logic;
        Cfg_AutoStart    : in    std_logic;
        -- Status
        Stat_State       : out   LinkState_t;
        Stat_Recovery    : out   std_logic;
        Stat_Cause       : out   ErrCause_t;
        Stat_TxCredit    : out   std_logic_vector(5 downto 0);
        Stat_RxCredit    : out   std_logic_vector(5 downto 0);
        Stat_TxLevel     : out   std_logic_vector(log2ceil(TxFifoDepth_g + 1) - 1 downto 0);
        Stat_RxLevel     : out   std_logic_vector(log2ceil(RxFifoDepth_g + 1) - 1 downto 0);
        Stat_Spill       : out   std_logic;
        Ev_CreditErr     : out   std_logic;
        Ev_RxOverflow    : out   std_logic;
        -- EDAC of the FIFOs: events on the read side, injection on the write side
        Ecc_TxSec        : out   std_logic;
        Ecc_TxDed        : out   std_logic;
        Ecc_RxSec        : out   std_logic; -- UserClk
        Ecc_RxDed        : out   std_logic; -- UserClk
        Inj_TxBitFlip    : in    std_logic_vector(eccCodewordWidth(9) - 1 downto 0) := (others => '0'); -- UserClk
        Inj_TxValid      : in    std_logic                                          := '0';               -- UserClk
        Inj_RxBitFlip    : in    std_logic_vector(eccCodewordWidth(9) - 1 downto 0) := (others => '0');
        Inj_RxValid      : in    std_logic                                          := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_dl is

    signal State       : LinkState_t;
    signal FifoRst     : std_logic;
    -- Transmit FIFO
    signal TxFifoData  : NChar_t;
    signal TxFifoDed   : std_logic;
    signal TxFifoSec   : std_logic;
    signal TxFifoValid : std_logic;
    signal TxFifoReady : std_logic;
    signal TxLevel     : std_logic_vector(log2ceil(TxFifoDepth_g + 1) - 1 downto 0);
    -- Receive FIFO
    signal RxFifoData  : NChar_t;
    signal RxFifoValid : std_logic;
    signal RxFifoReady : std_logic;
    signal RxLevel     : std_logic_vector(log2ceil(RxFifoDepth_g + 1) - 1 downto 0);
    signal RxOutData   : NChar_t;
    signal RxOutDed    : std_logic;
    signal RxOutSec    : std_logic;
    signal RxOutValid  : std_logic;
    signal RxOutReady  : std_logic;
    -- Flow control
    signal FctRequest  : std_logic;
    signal TxCreditAv  : std_logic;
    signal RxCreditAv  : std_logic;
    signal CreditErr   : std_logic;
    signal EepPending  : std_logic;
    -- Transmit scheduler
    signal SentNull    : std_logic;
    signal SentFct     : std_logic;
    signal SentNChar   : std_logic;
    -- Recovery
    signal RecStart    : std_logic;
    signal TxRecBusy   : std_logic;
    signal RxRecBusy   : std_logic;

    -- User side of the receive FIFO: double error containment
    type UserFsm_t is (Pass_s, Discard_s);

    signal UserFsm : UserFsm_t;

begin

    -- Port reset clears both FIFOs (ECSS 5.5.7.1e.1); the reset crossing of the FIFOs resets the user sides
    FifoRst <= Rst or Cfg_PortReset;

    -----------------------------------------------------------------------------------------------
    -- DL-1 Transmit FIFO
    -----------------------------------------------------------------------------------------------
    i_txfifo : entity olo.olo_ft_fifo_async
        generic map (
            Width_g         => 9,
            Depth_g         => TxFifoDepth_g,
            ReadyRstState_g => '0'
        )
        port map (
            In_Clk            => UserClk,
            In_Rst            => UserRst,
            In_Data           => TxUser_Data,
            In_Valid          => TxUser_Valid,
            In_Ready          => TxUser_Ready,
            Out_Clk           => Clk,
            Out_Rst           => FifoRst,
            Out_Data          => TxFifoData,
            Out_Valid         => TxFifoValid,
            Out_Ready         => TxFifoReady,
            Out_EccSec        => TxFifoSec,
            Out_EccDed        => TxFifoDed,
            Out_Level         => TxLevel,
            In_ErrInj_BitFlip => Inj_TxBitFlip,
            In_ErrInj_Valid   => Inj_TxValid
        );

    -- One event per word read
    Ecc_TxSec <= TxFifoSec and TxFifoValid and TxFifoReady;
    Ecc_TxDed <= TxFifoDed and TxFifoValid and TxFifoReady;

    -----------------------------------------------------------------------------------------------
    -- DL-2 Receive FIFO
    -----------------------------------------------------------------------------------------------
    i_rxfifo : entity olo.olo_ft_fifo_async
        generic map (
            Width_g         => 9,
            Depth_g         => RxFifoDepth_g,
            ReadyRstState_g => '0'
        )
        port map (
            In_Clk            => Clk,
            In_Rst            => FifoRst,
            In_Data           => RxFifoData,
            In_Valid          => RxFifoValid,
            In_Ready          => RxFifoReady,
            In_Level          => RxLevel,
            Out_Clk           => UserClk,
            Out_Rst           => UserRst,
            Out_Data          => RxOutData,
            Out_Valid         => RxOutValid,
            Out_Ready         => RxOutReady,
            Out_EccSec        => RxOutSec,
            Out_EccDed        => RxOutDed,
            In_ErrInj_BitFlip => Inj_RxBitFlip,
            In_ErrInj_Valid   => Inj_RxValid
        );

    Ecc_RxSec <= RxOutSec and RxOutValid and RxOutReady;
    Ecc_RxDed <= RxOutDed and RxOutValid and RxOutReady;

    -- A double error is passed as an EEP, then the N-Chars up to the next end of packet marker are discarded
    p_user : process (UserClk) is
    begin
        if rising_edge(UserClk) then

            case UserFsm is

                when Pass_s =>
                    if RxOutValid = '1' and RxOutDed = '1' and RxUser_Ready = '1' then
                        UserFsm <= Discard_s;
                    end if;

                when others =>
                    if RxOutValid = '1' and RxOutDed = '0' and RxOutData(NCharFlagIdx_c) = '1' then
                        UserFsm <= Pass_s;
                    end if;

            end case;

            if UserRst = '1' then
                UserFsm <= Pass_s;
            end if;
        end if;
    end process;

    RxUser_Data  <= NCharEep_c when RxOutDed = '1' else RxOutData;
    RxUser_Valid <= RxOutValid when UserFsm = Pass_s else '0';
    RxOutReady   <= RxUser_Ready when UserFsm = Pass_s else '1';

    -----------------------------------------------------------------------------------------------
    -- DL-3 Link state machine
    -----------------------------------------------------------------------------------------------
    i_lsm : entity work.owr_dl_lsm
        generic map (
            ErrorResetCycles_g => timeCycles(TimeErrorReset_c, ClkFreq_g),
            TimeoutCycles_g    => timeCycles(TimeErrorWait_c, ClkFreq_g)
        )
        port map (
            Clk              => Clk,
            Rst              => Rst,
            Cfg_PortReset    => Cfg_PortReset,
            Cfg_LinkDisabled => Cfg_LinkDisabled,
            Cfg_LinkStart    => Cfg_LinkStart,
            Cfg_AutoStart    => Cfg_AutoStart,
            Rx_GotNull       => Rx_GotNull,
            Rx_ParityErr     => Rx_ParityErr,
            Rx_EscErr        => Rx_EscErr,
            Rx_Disconnect    => Rx_Disconnect,
            RxChar_Valid     => RxChar_Valid,
            RxChar_Kind      => RxChar_Kind,
            Fc_CreditErr     => CreditErr,
            Tx_SentNull      => SentNull,
            Tx_SentFct       => SentFct,
            TxEnable         => TxEnable,
            RxEnable         => RxEnable,
            State            => State
        );

    TxRun <= '1' when State = StateRun_c else '0';

    -----------------------------------------------------------------------------------------------
    -- DL-4 Flow control manager
    -----------------------------------------------------------------------------------------------
    i_fc : entity work.owr_dl_fc
        generic map (
            RxFifoDepth_g => RxFifoDepth_g
        )
        port map (
            Clk           => Clk,
            Rst           => Rst,
            State         => State,
            RxChar_Valid  => RxChar_Valid,
            RxChar_Kind   => RxChar_Kind,
            Tx_FctSent    => SentFct,
            Tx_NCharSent  => SentNChar,
            RxFifo_Level  => to_integer(unsigned(RxLevel)),
            Rx_EepPending => EepPending,
            FctRequest    => FctRequest,
            TxCreditAvail => TxCreditAv,
            RxCreditAvail => RxCreditAv,
            CreditErr     => CreditErr,
            TxCredit      => Stat_TxCredit,
            RxCredit      => Stat_RxCredit
        );

    -----------------------------------------------------------------------------------------------
    -- DL-5 Transmit scheduler
    -----------------------------------------------------------------------------------------------
    i_tx : entity work.owr_dl_tx
        port map (
            Clk              => Clk,
            Rst              => Rst,
            State            => State,
            Cfg_PortReset    => Cfg_PortReset,
            Fc_FctRequest    => FctRequest,
            Fc_TxCreditAvail => TxCreditAv,
            TxFifo_Data      => TxFifoData,
            TxFifo_Ded       => TxFifoDed,
            TxFifo_Valid     => TxFifoValid,
            TxFifo_Ready     => TxFifoReady,
            TxBc_Data        => TxBc_Data,
            TxBc_Valid       => TxBc_Valid,
            TxBc_Ready       => TxBc_Ready,
            TxBc_Discarded   => TxBc_Discarded,
            Rec_Start        => RecStart,
            Rec_Busy         => TxRecBusy,
            TxChar_Kind      => TxChar_Kind,
            TxChar_Data      => TxChar_Data,
            TxChar_Ack       => TxChar_Ack,
            SentNull         => SentNull,
            SentFct          => SentFct,
            SentNChar        => SentNChar,
            Stat_Spill       => Stat_Spill
        );

    -----------------------------------------------------------------------------------------------
    -- DL-6 Receive handler
    -----------------------------------------------------------------------------------------------
    i_rx : entity work.owr_dl_rx
        port map (
            Clk              => Clk,
            Rst              => Rst,
            State            => State,
            Cfg_PortReset    => Cfg_PortReset,
            RxChar_Valid     => RxChar_Valid,
            RxChar_Kind      => RxChar_Kind,
            RxChar_Data      => RxChar_Data,
            Fc_RxCreditAvail => RxCreditAv,
            RxFifo_Data      => RxFifoData,
            RxFifo_Valid     => RxFifoValid,
            RxFifo_Ready     => RxFifoReady,
            RxBc_Data        => RxBc_Data,
            RxBc_Valid       => RxBc_Valid,
            Rec_Start        => RecStart,
            Rec_Busy         => RxRecBusy,
            EepPending       => EepPending,
            Ev_Overflow      => Ev_RxOverflow
        );

    -----------------------------------------------------------------------------------------------
    -- DL-7 Link error recovery
    -----------------------------------------------------------------------------------------------
    i_rec : entity work.owr_dl_rec
        port map (
            Clk              => Clk,
            Rst              => Rst,
            State            => State,
            Cfg_PortReset    => Cfg_PortReset,
            Cfg_LinkDisabled => Cfg_LinkDisabled,
            Rx_Disconnect    => Rx_Disconnect,
            Rx_ParityErr     => Rx_ParityErr,
            Rx_EscErr        => Rx_EscErr,
            Fc_CreditErr     => CreditErr,
            Rec_Start        => RecStart,
            Tx_RecBusy       => TxRecBusy,
            Rx_RecBusy       => RxRecBusy,
            Stat_Recovery    => Stat_Recovery,
            Stat_Cause       => Stat_Cause
        );

    -- Status
    Stat_State   <= State;
    Stat_TxLevel <= TxLevel;
    Stat_RxLevel <= RxLevel;
    Ev_CreditErr <= CreditErr;

end architecture;
