---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Common constants, types and functions of OpenWire: character kinds, N-Char format, link states,
-- broadcast code fields and timer conversions (ECSS-E-ST-50-12C Rev.1).
--
-- Documentation: hdl/owr_pkg/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package owr_pkg is

    -- *** Characters (ECSS 5.4.3) ***

    -- Kind of a character or control code between the Data Link and the Encoding layer
    subtype CharKind_t is std_logic_vector(2 downto 0);

    constant KindNull_c : CharKind_t := "000"; -- Null control code (ESC FCT)
    constant KindFct_c  : CharKind_t := "001"; -- Flow control token
    constant KindData_c : CharKind_t := "010"; -- Data character
    constant KindEop_c  : CharKind_t := "011"; -- End of packet marker
    constant KindEep_c  : CharKind_t := "100"; -- Error end of packet marker
    constant KindBc_c   : CharKind_t := "101"; -- Broadcast code (ESC data character)

    -- Two-bit control type of a control character, bit 0 is sent first (ECSS 5.4.3.2)
    subtype CtrlType_t is std_logic_vector(1 downto 0);

    constant CtrlFct_c : CtrlType_t := "00";
    constant CtrlEop_c : CtrlType_t := "10";
    constant CtrlEep_c : CtrlType_t := "01";
    constant CtrlEsc_c : CtrlType_t := "11";

    -- *** N-Chars on the FIFOs and packet ports ***

    -- N-Char: bit 8 set marks the end of packet marker, bits 7:0 are the data character or, for a marker,
    -- 0x00 (EOP) or 0x01 (EEP)
    subtype NChar_t is std_logic_vector(8 downto 0);

    constant NCharFlagIdx_c : natural := 8;
    constant NCharEop_c     : NChar_t := '1' & x"00";
    constant NCharEep_c     : NChar_t := '1' & x"01";

    -- *** Link state machine (ECSS 5.5.7) ***

    subtype LinkState_t is std_logic_vector(2 downto 0);

    constant StateErrorReset_c : LinkState_t := "000";
    constant StateErrorWait_c  : LinkState_t := "001";
    constant StateReady_c      : LinkState_t := "010";
    constant StateStarted_c    : LinkState_t := "011";
    constant StateConnecting_c : LinkState_t := "100";
    constant StateRun_c        : LinkState_t := "101";

    -- Cause of the last error recovery (ECSS 5.5.8.4a.5)
    subtype ErrCause_t is std_logic_vector(2 downto 0);

    constant CauseNone_c         : ErrCause_t := "000";
    constant CauseLinkDisabled_c : ErrCause_t := "001";
    constant CauseDisconnect_c   : ErrCause_t := "010";
    constant CauseParity_c       : ErrCause_t := "011";
    constant CauseEsc_c          : ErrCause_t := "100";
    constant CauseCredit_c       : ErrCause_t := "101";

    -- *** Flow control (ECSS 5.5.4) ***

    constant CreditMax_c    : natural := 56;
    constant CreditPerFct_c : natural := 8;
    subtype Credit_t is natural range 0 to CreditMax_c;

    -- *** Broadcast codes (ECSS 5.4.3.3, 5.6.3) ***

    -- Type field (bits 7:6) of a broadcast code
    subtype BcType_t is std_logic_vector(1 downto 0);

    constant BcTypeTimeCode_c  : BcType_t := "00";
    constant BcTypeInterrupt_c : BcType_t := "10";

    -- Bit 5 of the value field of a distributed interrupt code: '1' for an acknowledgement (ECSS 5.6.5.3c)
    constant BcAckIdx_c : natural := 5;

    -- Kind of a broadcast request or indication between the user ports and the Network layer
    subtype BcKind_t is std_logic_vector(1 downto 0);

    constant BcKindTimeCode_c  : BcKind_t := "00";
    constant BcKindInterrupt_c : BcKind_t := "01";
    constant BcKindAck_c       : BcKind_t := "10";

    -- Broadcast request or indication on the crossing FIFOs: kind (7:6) and value (5:0)
    subtype BcEntry_t is std_logic_vector(7 downto 0);

    -- *** Timing (ECSS 5.4.8, 5.4.10, 5.5.7) ***

    constant TimeErrorReset_c : real := 6.4e-6;   -- "after 6.4 us", 5.82 us to 7.22 us
    constant TimeErrorWait_c  : real := 12.8e-6;  -- "after 12.8 us", 11.64 us to 14.33 us
    constant TimeDisconnect_c : real := 850.0e-9; -- disconnect timeout, 727 ns to 1 us
    constant RateInit_c       : real := 10.0e6;   -- initial data signalling rate, 10 Mb/s +/- 1 Mb/s

    -- Number of clock cycles of a duration (rounded to the nearest cycle)
    function timeCycles (
        duration : in real;
        freq     : in real) return natural;

    -- Bit period in clock cycles of the initial data signalling rate
    function initDivider (freq : in real) return positive;

    -- Odd parity bit of a character: covers the data or control bits of the previous character (prevBits is
    -- their XOR), the parity bit itself and the data-control flag (ECSS 5.4.3.4)
    function parityBit (
        prevBits : in std_logic;
        ctrlFlag : in std_logic) return std_logic;

    -- XOR of all bits of a vector
    function xorReduce (vec : in std_logic_vector) return std_logic;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body owr_pkg is

    function timeCycles (
        duration : in real;
        freq     : in real) return natural is
    begin
        return natural(round(duration * freq));
    end function;

    function initDivider (freq : in real) return positive is
        variable Div_v : positive;
    begin
        Div_v := maximum(1, integer(round(freq / RateInit_c)));
        return Div_v;
    end function;

    function parityBit (
        prevBits : in std_logic;
        ctrlFlag : in std_logic) return std_logic is
    begin
        -- prevBits xor P xor flag must be '1'
        return not (prevBits xor ctrlFlag);
    end function;

    function xorReduce (vec : in std_logic_vector) return std_logic is
        variable Res_v : std_logic := '0';
    begin

        for i in vec'range loop
            Res_v := Res_v xor vec(i);
        end loop;

        return Res_v;
    end function;

end package body;
