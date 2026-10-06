---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Character-level model of a SpaceWire far end (ECSS-E-ST-50-12C Rev.1 clauses 5.4.3 and 5.4.4):
-- character encoding with odd parity and the protected type of the control object of the Data-Strobe
-- model owr_tb_ds_bfm (transmit queue, bit period, modes, fault injection, log of the decoded
-- characters). The object itself is in owr_tb_farend_pkg.
-- The encoder and decoder are independent of the RTL and work in continuous time.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package owr_tb_ds_pkg is

    -- Maximum number of model instances in one testbench
    constant TbInstances_c : positive := 4;

    -- Characters of the model. TbEsc is a single escape character (to build illegal sequences), TbRaw sends the bits
    -- Raw(RawLen-1 downto 0), bit 0 first, without encoding (the next parity bit is computed as after an FCT).
    type TbCharKind_t is (TbNull, TbFct, TbData, TbEop, TbEep, TbEsc, TbBc, TbRaw);

    type TbChar_t is record
        Kind   : TbCharKind_t;
        Data   : std_logic_vector(7 downto 0);
        T      : time;    -- time of the first bit (decoded characters)
        ParErr : boolean; -- transmit: send this character with an inverted parity bit
        Raw    : std_logic_vector(13 downto 0);
        RawLen : natural range 0 to 14;
    end record;

    constant TbCharInit_c : TbChar_t := (Kind => TbNull, Data => x"00", T => 0 ns, ParErr => false,
                                         Raw => (others => '0'), RawLen => 0);

    -- Bits of an encoded character or control code, bit 0 is sent first
    type TbBits_t is record
        Bits : std_logic_vector(13 downto 0);
        Len  : natural range 0 to 14;
        Acc  : std_logic; -- XOR of the data or control bits of the last character (for the next parity bit)
    end record;

    -- Encodes a character after a character whose data or control bits have the XOR prevAcc
    function tbEncode (
        char    : in TbChar_t;
        prevAcc : in std_logic) return TbBits_t;

    -- Constructors
    function tbChar (
        kind : in TbCharKind_t;
        data : in std_logic_vector(7 downto 0) := x"00";
        parErr : in boolean := false) return TbChar_t;

    function tbData (data : in natural) return TbChar_t;

    -- Raw bits, given in the order they are sent (left character first)
    function tbRaw (bits : in string) return TbChar_t;

    function tbTimeCode (value : in natural) return TbChar_t;

    function tbInterrupt (iid : in natural) return TbChar_t;

    function tbIntAck (iid : in natural) return TbChar_t;

    function tbKindStr (kind : in TbCharKind_t) return string;

    -- Transmit modes of the model
    type TbTxMode_t is (
        TbModeOff,   -- transmitter disabled: data and strobe reset to zero (strobe first, then data)
        TbModeNull,  -- queued characters, Nulls when the queue is empty
        TbModeSilent -- queued characters, then no transition (the far end of the port detects a disconnect)
    );

    -- Edge on the data or strobe line received by the model
    type TbEdge_t is record
        T : time;
        D : std_logic;
        S : std_logic;
    end record;

    type TbFarEnd_t is protected

        -- Transmitter
        procedure txPush (
            idx  : natural;
            char : TbChar_t);

        impure function txCount (idx : natural) return natural;
        impure function txPop (idx : natural) return TbChar_t;
        impure function txPeek (idx : natural) return TbChar_t;

        -- Removes the head of the queue (a procedure: an optimising simulator may skip a function call whose
        -- result is not used)
        procedure txDrop (idx : natural);

        procedure txClear (idx : natural);

        procedure setBitPeriod (
            idx    : natural;
            period : time);

        impure function getBitPeriod (idx : natural) return time;

        procedure setMode (
            idx  : natural;
            mode : TbTxMode_t);

        impure function getMode (idx : natural) return TbTxMode_t;

        -- Next bit is replaced by a simultaneous transition of data and strobe
        procedure requestSimultaneous (idx : natural);

        impure function takeSimultaneous (idx : natural) return boolean;

        -- Time of the last transition sent by the model
        procedure setTxEdge (idx : natural);

        impure function getTxEdge (idx : natural) return time;

        -- Number of characters sent since the last clear (Nulls of the idle mode included)
        procedure countSent (
            idx  : natural;
            kind : TbCharKind_t);

        impure function sentCount (
            idx  : natural;
            kind : TbCharKind_t) return natural;

        -- Receiver (decoder of the port output). Nulls are counted, and logged only with setLogNulls.
        procedure setLogNulls (
            idx : natural;
            ena : boolean);

        impure function rxKindCount (
            idx  : natural;
            kind : TbCharKind_t) return natural;

        -- Time without edge after which the decoder searches for a new first Null (default 2 us)
        procedure setRxTimeout (
            idx     : natural;
            timeout : time);

        impure function getRxTimeout (idx : natural) return time;

        procedure rxPush (
            idx  : natural;
            char : TbChar_t);

        impure function rxCount (idx : natural) return natural;
        impure function rxGet (
            idx : natural;
            n   : natural) return TbChar_t;

        procedure rxClear (idx : natural);

        procedure rxError (idx : natural);

        impure function rxErrors (idx : natural) return natural;

        procedure edgePush (
            idx  : natural;
            edge : TbEdge_t);

        impure function edgeCount (idx : natural) return natural;
        impure function edgeGet (
            idx : natural;
            n   : natural) return TbEdge_t;

    end protected;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body owr_tb_ds_pkg is

    function tbEncode (
        char    : in TbChar_t;
        prevAcc : in std_logic) return TbBits_t is
        variable Res_v  : TbBits_t;
        variable Typ_v  : std_logic_vector(1 downto 0);
        variable Par_v  : std_logic;
        variable Acc_v  : std_logic;
        variable Ctrl_v : boolean;
    begin
        Res_v.Bits := (others => '0');

        case char.Kind is

            when TbRaw =>
                Res_v.Bits := char.Raw;
                Res_v.Len  := char.RawLen;
                Res_v.Acc  := '0';
                return Res_v;

            when TbNull | TbBc =>
                -- ESC: P 1 1 1, then FCT (P 1 0 0) or a data character
                Par_v         := not (prevAcc xor '1');
                Res_v.Bits(0) := Par_v;
                Res_v.Bits(1) := '1';
                Res_v.Bits(2) := '1';
                Res_v.Bits(3) := '1';
                if char.Kind = TbNull then
                    Res_v.Bits(4) := not ('0' xor '1'); -- ESC bits 11 have XOR 0
                    Res_v.Bits(5) := '1';
                    Res_v.Bits(6) := '0';
                    Res_v.Bits(7) := '0';
                    Res_v.Len     := 8;
                    Res_v.Acc     := '0';
                else
                    Res_v.Bits(4) := not ('0' xor '0');
                    Res_v.Bits(5) := '0';
                    Acc_v         := '0';

                    for i in 0 to 7 loop
                        Res_v.Bits(6 + i) := char.Data(i);
                        Acc_v             := Acc_v xor char.Data(i);
                    end loop;

                    Res_v.Len := 14;
                    Res_v.Acc := Acc_v;
                end if;
                if char.ParErr then
                    Res_v.Bits(0) := not Res_v.Bits(0);
                end if;
                return Res_v;

            when TbData =>
                Ctrl_v := false;

            when TbFct =>
                Ctrl_v := true;
                Typ_v  := "00";

            when TbEop =>
                Ctrl_v := true;
                Typ_v  := "10";

            when TbEep =>
                Ctrl_v := true;
                Typ_v  := "01";

            when TbEsc =>
                Ctrl_v := true;
                Typ_v  := "11";

        end case;

        if Ctrl_v then
            Res_v.Bits(0) := not (prevAcc xor '1');
            Res_v.Bits(1) := '1';
            Res_v.Bits(2) := Typ_v(0);
            Res_v.Bits(3) := Typ_v(1);
            Res_v.Len     := 4;
            Res_v.Acc     := Typ_v(0) xor Typ_v(1);
        else
            Res_v.Bits(0) := not (prevAcc xor '0');
            Res_v.Bits(1) := '0';
            Acc_v         := '0';

            for i in 0 to 7 loop
                Res_v.Bits(2 + i) := char.Data(i);
                Acc_v             := Acc_v xor char.Data(i);
            end loop;

            Res_v.Len := 10;
            Res_v.Acc := Acc_v;
        end if;
        if char.ParErr then
            Res_v.Bits(0) := not Res_v.Bits(0);
        end if;
        return Res_v;
    end function;

    function tbChar (
        kind : in TbCharKind_t;
        data : in std_logic_vector(7 downto 0) := x"00";
        parErr : in boolean := false) return TbChar_t is
        variable Res_v : TbChar_t := TbCharInit_c;
    begin
        Res_v.Kind   := kind;
        Res_v.Data   := data;
        Res_v.ParErr := parErr;
        return Res_v;
    end function;

    function tbData (data : in natural) return TbChar_t is
    begin
        return tbChar(TbData, std_logic_vector(to_unsigned(data mod 256, 8)));
    end function;

    function tbRaw (bits : in string) return TbChar_t is
        variable Res_v : TbChar_t := TbCharInit_c;
    begin
        Res_v.Kind   := TbRaw;
        Res_v.RawLen := bits'length;

        for i in 0 to bits'length - 1 loop
            if bits(bits'low + i) = '1' then
                Res_v.Raw(i) := '1';
            end if;
        end loop;

        return Res_v;
    end function;

    function tbTimeCode (value : in natural) return TbChar_t is
    begin
        return tbChar(TbBc, "00" & std_logic_vector(to_unsigned(value mod 64, 6)));
    end function;

    function tbInterrupt (iid : in natural) return TbChar_t is
    begin
        return tbChar(TbBc, "100" & std_logic_vector(to_unsigned(iid mod 32, 5)));
    end function;

    function tbIntAck (iid : in natural) return TbChar_t is
    begin
        return tbChar(TbBc, "101" & std_logic_vector(to_unsigned(iid mod 32, 5)));
    end function;

    function tbKindStr (kind : in TbCharKind_t) return string is
    begin

        case kind is

            when TbNull =>
                return "Null";

            when TbFct =>
                return "FCT";

            when TbData =>
                return "Data";

            when TbEop =>
                return "EOP";

            when TbEep =>
                return "EEP";

            when TbEsc =>
                return "ESC";

            when TbBc =>
                return "BC";

            when TbRaw =>
                return "Raw";

        end case;

    end function;

    type TbFarEnd_t is protected body

        constant QueueSize_c : positive := 65536;
        constant EdgeSize_c  : positive := 8192;

        type CharArray_t is array (0 to QueueSize_c - 1) of TbChar_t;
        type EdgeArray_t is array (0 to EdgeSize_c - 1) of TbEdge_t;
        type CharArrayPtr_t is access CharArray_t;
        type EdgeArrayPtr_t is access EdgeArray_t;
        type CharArrays_t is array (0 to TbInstances_c - 1) of CharArrayPtr_t;
        type EdgeArrays_t is array (0 to TbInstances_c - 1) of EdgeArrayPtr_t;
        type NatArray_t is array (0 to TbInstances_c - 1) of natural;
        type TimeArray_t is array (0 to TbInstances_c - 1) of time;
        type ModeArray_t is array (0 to TbInstances_c - 1) of TbTxMode_t;
        type BoolArray_t is array (0 to TbInstances_c - 1) of boolean;
        type KindCount_t is array (TbCharKind_t) of natural;
        type KindCounts_t is array (0 to TbInstances_c - 1) of KindCount_t;

        variable TxQ_v     : CharArrays_t;
        variable TxHead_v  : NatArray_t   := (others => 0);
        variable TxCnt_v   : NatArray_t   := (others => 0);
        variable Period_v  : TimeArray_t  := (others => 100 ns);
        variable Mode_v    : ModeArray_t  := (others => TbModeOff);
        variable Simul_v   : BoolArray_t  := (others => false);
        variable TxEdge_v  : TimeArray_t  := (others => 0 ns);
        variable Sent_v    : KindCounts_t := (others => (others => 0));
        variable RxLog_v   : CharArrays_t;
        variable RxCnt_v   : NatArray_t   := (others => 0);
        variable RxKind_v  : KindCounts_t := (others => (others => 0));
        variable LogNull_v : BoolArray_t  := (others => false);
        variable RxTo_v    : TimeArray_t  := (others => 2 us);
        variable RxErr_v   : NatArray_t   := (others => 0);
        variable EdgeLog_v : EdgeArrays_t;
        variable EdgeCnt_v : NatArray_t   := (others => 0);

        procedure allocate (idx : natural) is
        begin
            if TxQ_v(idx) = null then
                TxQ_v(idx)     := new CharArray_t;
                RxLog_v(idx)   := new CharArray_t;
                EdgeLog_v(idx) := new EdgeArray_t;
            end if;
        end procedure;

        procedure txPush (
            idx  : natural;
            char : TbChar_t) is
        begin
            allocate(idx);
            assert TxCnt_v(idx) < QueueSize_c
                report "owr_tb_ds_pkg: transmit queue full"
                severity failure;
            TxQ_v(idx)((TxHead_v(idx) + TxCnt_v(idx)) mod QueueSize_c) := char;
            TxCnt_v(idx)                                               := TxCnt_v(idx) + 1;
        end procedure;

        impure function txCount (idx : natural) return natural is
        begin
            return TxCnt_v(idx);
        end function;

        impure function txPop (idx : natural) return TbChar_t is
            variable Char_v : TbChar_t;
        begin
            Char_v        := TxQ_v(idx)(TxHead_v(idx));
            TxHead_v(idx) := (TxHead_v(idx) + 1) mod QueueSize_c;
            TxCnt_v(idx)  := TxCnt_v(idx) - 1;
            return Char_v;
        end function;

        impure function txPeek (idx : natural) return TbChar_t is
        begin
            return TxQ_v(idx)(TxHead_v(idx));
        end function;

        procedure txDrop (idx : natural) is
        begin
            if TxCnt_v(idx) > 0 then
                TxHead_v(idx) := (TxHead_v(idx) + 1) mod QueueSize_c;
                TxCnt_v(idx)  := TxCnt_v(idx) - 1;
            end if;
        end procedure;

        procedure txClear (idx : natural) is
        begin
            TxCnt_v(idx) := 0;
        end procedure;

        procedure setBitPeriod (
            idx    : natural;
            period : time) is
        begin
            Period_v(idx) := period;
        end procedure;

        impure function getBitPeriod (idx : natural) return time is
        begin
            return Period_v(idx);
        end function;

        procedure setMode (
            idx  : natural;
            mode : TbTxMode_t) is
        begin
            Mode_v(idx) := mode;
        end procedure;

        impure function getMode (idx : natural) return TbTxMode_t is
        begin
            return Mode_v(idx);
        end function;

        procedure requestSimultaneous (idx : natural) is
        begin
            Simul_v(idx) := true;
        end procedure;

        impure function takeSimultaneous (idx : natural) return boolean is
            variable Res_v : boolean;
        begin
            Res_v        := Simul_v(idx);
            Simul_v(idx) := false;
            return Res_v;
        end function;

        procedure setTxEdge (idx : natural) is
        begin
            TxEdge_v(idx) := now;
        end procedure;

        impure function getTxEdge (idx : natural) return time is
        begin
            return TxEdge_v(idx);
        end function;

        procedure countSent (
            idx  : natural;
            kind : TbCharKind_t) is
        begin
            Sent_v(idx)(kind) := Sent_v(idx)(kind) + 1;
        end procedure;

        impure function sentCount (
            idx  : natural;
            kind : TbCharKind_t) return natural is
        begin
            return Sent_v(idx)(kind);
        end function;

        procedure setLogNulls (
            idx : natural;
            ena : boolean) is
        begin
            LogNull_v(idx) := ena;
        end procedure;

        impure function rxKindCount (
            idx  : natural;
            kind : TbCharKind_t) return natural is
        begin
            return RxKind_v(idx)(kind);
        end function;

        procedure setRxTimeout (
            idx     : natural;
            timeout : time) is
        begin
            RxTo_v(idx) := timeout;
        end procedure;

        impure function getRxTimeout (idx : natural) return time is
        begin
            return RxTo_v(idx);
        end function;

        procedure rxPush (
            idx  : natural;
            char : TbChar_t) is
        begin
            allocate(idx);
            RxKind_v(idx)(char.Kind) := RxKind_v(idx)(char.Kind) + 1;
            if char.Kind = TbNull and not LogNull_v(idx) then
                return;
            end if;
            if RxCnt_v(idx) < QueueSize_c then
                RxLog_v(idx)(RxCnt_v(idx)) := char;
            end if;
            RxCnt_v(idx) := RxCnt_v(idx) + 1;
        end procedure;

        impure function rxCount (idx : natural) return natural is
        begin
            return RxCnt_v(idx);
        end function;

        impure function rxGet (
            idx : natural;
            n   : natural) return TbChar_t is
        begin
            assert n < RxCnt_v(idx) and n < QueueSize_c
                report "owr_tb_ds_pkg: receive log index out of range"
                severity failure;
            return RxLog_v(idx)(n);
        end function;

        procedure rxClear (idx : natural) is
        begin
            RxCnt_v(idx)   := 0;
            RxKind_v(idx)  := (others => 0);
            RxErr_v(idx)   := 0;
            EdgeCnt_v(idx) := 0;
            Sent_v(idx)    := (others => 0);
        end procedure;

        procedure rxError (idx : natural) is
        begin
            RxErr_v(idx) := RxErr_v(idx) + 1;
        end procedure;

        impure function rxErrors (idx : natural) return natural is
        begin
            return RxErr_v(idx);
        end function;

        procedure edgePush (
            idx  : natural;
            edge : TbEdge_t) is
        begin
            allocate(idx);
            if EdgeCnt_v(idx) < EdgeSize_c then
                EdgeLog_v(idx)(EdgeCnt_v(idx)) := edge;
            end if;
            EdgeCnt_v(idx) := EdgeCnt_v(idx) + 1;
        end procedure;

        impure function edgeCount (idx : natural) return natural is
        begin
            return EdgeCnt_v(idx);
        end function;

        impure function edgeGet (
            idx : natural;
            n   : natural) return TbEdge_t is
        begin
            assert n < EdgeCnt_v(idx) and n < EdgeSize_c
                report "owr_tb_ds_pkg: edge log index out of range"
                severity failure;
            return EdgeLog_v(idx)(n);
        end function;

    end protected body;

end package body;
