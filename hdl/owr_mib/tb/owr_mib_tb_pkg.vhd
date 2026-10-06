---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Types of the MIB testbench: status and event inputs of owr_mib and its observed outputs.
--
-- Documentation: hdl/owr_mib/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.owr_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package owr_mib_tb_pkg is

    -- Inputs of the MIB driven by the test sequencer (one-cycle events in their clock domain)
    type MibIn_t is record
        State     : LinkState_t;
        Recovery  : std_logic;
        GotNull   : std_logic;
        Spill     : std_logic;
        Cause     : ErrCause_t;
        TxCredit  : std_logic_vector(5 downto 0);
        RxCredit  : std_logic_vector(5 downto 0);
        TxLevel   : std_logic_vector(15 downto 0);
        RxLevel   : std_logic_vector(15 downto 0);
        TimeCode  : std_logic_vector(5 downto 0);
        IntActive : std_logic_vector(31 downto 0);
        -- Events in LinkClk: 0 disconnect, 1 parity, 2 ESC, 3 credit, 4 TC valid, 5 TC invalid, 6 interrupt,
        -- 7 acknowledgement, 8 BC discarded, 9 BC ignored, 10 interrupt request discarded, 11 acknowledgement
        -- request discarded, 12 indication overflow, 13 receive overflow
        Ev        : std_logic_vector(13 downto 0);
        AckIid    : std_logic_vector(4 downto 0);
        -- ECC events: LinkClk (Tx, BcReq), UserClk (Rx, BcInd); bit 0 SEC, bit 1 DED
        EccTx     : std_logic_vector(1 downto 0);
        EccBcReq  : std_logic_vector(1 downto 0);
        EccRx     : std_logic_vector(1 downto 0);
        EccBcInd  : std_logic_vector(1 downto 0);
    end record;

    constant MibInInit_c : MibIn_t := (
        State     => StateErrorReset_c,
        Recovery  => '0',
        GotNull   => '0',
        Spill     => '0',
        Cause     => CauseNone_c,
        TxCredit  => (others => '0'),
        RxCredit  => (others => '0'),
        TxLevel   => (others => '0'),
        RxLevel   => (others => '0'),
        TimeCode  => (others => '0'),
        IntActive => (others => '0'),
        Ev        => (others => '0'),
        AckIid    => (others => '0'),
        EccTx     => "00",
        EccBcReq  => "00",
        EccRx     => "00",
        EccBcInd  => "00"
    );

    -- Observed outputs: levels and counters of the command pulses
    type MibOut_t is record
        LinkDisabled : std_logic;
        LinkStart    : std_logic;
        AutoStart    : std_logic;
        DriverEn     : std_logic;
        ReceiverEn   : std_logic;
        Loopback     : std_logic;
        RunDiv       : std_logic_vector(7 downto 0);
        AckMode      : std_logic;
        IntTick      : std_logic_vector(15 downto 0);
        IntHoldoff   : std_logic_vector(15 downto 0);
        AckDelay     : std_logic_vector(15 downto 0);
        Irq          : std_logic;
        CntPortReset : natural;
        CntTc        : natural;
        LastTc       : std_logic_vector(5 downto 0);
        CntInt       : natural;
        LastInt      : std_logic_vector(4 downto 0);
        CntAck       : natural;
        LastAck      : std_logic_vector(4 downto 0);
        -- Injection pulses per FIFO and the number of flipped bits of the last one
        CntInjTx     : natural;
        BitsInjTx    : natural;
        CntInjRx     : natural;
        BitsInjRx    : natural;
        CntInjBcReq  : natural;
        BitsInjBcReq : natural;
        CntInjBcInd  : natural;
        BitsInjBcInd : natural;
    end record;

    -- AXI4-Lite VVC instance
    constant Axi_c : natural := 0;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body owr_mib_tb_pkg is

end package body;
