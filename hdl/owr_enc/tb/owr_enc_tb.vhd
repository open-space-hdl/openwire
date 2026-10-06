---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the Encoding layer (EN-1 to EN-3) against the Data-Strobe far-end model.
--
-- Documentation: hdl/owr_enc/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_context;

library work;
    use work.owr_pkg.all;
    use work.owr_tb_pkg.all;
    use work.owr_tb_ds_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_enc_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_enc_tb is

    -- Model instances: 0 = far end, 1 = queue of the port transmitter and log of the port receiver
    constant Far_c  : natural := 0;
    constant Port_c : natural := 1;

    signal Clk           : std_logic;
    signal Rst           : std_logic                    := '1';
    signal TxEnable      : std_logic                    := '0';
    signal RxEnable      : std_logic                    := '0';
    signal TxRun         : std_logic                    := '0';
    signal Cfg_RunDiv    : std_logic_vector(7 downto 0) := x"01";
    signal Cfg_Loopback  : std_logic                    := '0';
    signal Rx_GotNull    : std_logic;
    signal ParityErrCnt  : natural;
    signal EscErrCnt     : natural;
    signal DisconnectCnt : natural;
    signal DisconnectT   : time;
    signal TxAckCnt      : natural;
    signal Spw_DOut      : std_logic;
    signal Spw_SOut      : std_logic;

    -- Deterministic character sequence of all kinds: character i of sequence seed
    function seqChar (
        i    : natural;
        seed : natural;
        bc   : boolean := true) return TbChar_t is
        variable H_v    : natural;
        variable Kind_v : natural;
    begin
        H_v    := ((i + 1) * 7919 + seed * 104729) mod 65521;
        Kind_v := H_v mod 16;
        if i = 0 then
            return tbData(H_v / 16);
        end if;

        case Kind_v is

            when 0 =>
                return tbChar(TbFct);

            when 1 =>
                return tbChar(TbEop);

            when 2 =>
                return tbChar(TbEep);

            when 3 =>
                return tbChar(TbNull);

            when 4 | 5 =>
                if bc then
                    return tbChar(TbBc, std_logic_vector(to_unsigned(H_v / 16 mod 256, 8)));
                else
                    return tbData(H_v / 16);
                end if;

            when others =>
                return tbData(H_v / 16);

        end case;

    end function;

begin

    test_runner_watchdog(runner, 50 ms);

    p_main : process is
        variable Start_v : natural;
        variable Cnt_v   : natural;
        variable Char_v  : TbChar_t;
        variable Exp_v   : TbChar_t;
        variable Edge_v  : TbEdge_t;
        variable Prev_v  : TbEdge_t;
        variable T_v     : time;
        variable Ok_v    : boolean;
        variable Both_v  : boolean;
        variable Errs_v  : natural;

        -- Compares n entries of the log of instance idx from entry first with the sequence seed
        procedure checkSeq (
            idx   : natural;
            first : natural;
            n     : natural;
            seed  : natural;
            bc    : boolean;
            msg   : string) is
            variable Mism_v : natural := 0;
            variable Pos_v  : integer := -1;
            variable Act_v  : TbChar_t;
            variable Ref_v  : TbChar_t;
        begin
            check_value(FarEnd_v.rxCount(idx) >= first + n, error, msg & ": number of characters (" &
                        to_string(FarEnd_v.rxCount(idx) - first) & ")");
            if FarEnd_v.rxCount(idx) >= first + n then

                for i in 0 to n - 1 loop
                    Act_v := FarEnd_v.rxGet(idx, first + i);
                    Ref_v := seqChar(i, seed, bc);
                    if Act_v.Kind /= Ref_v.Kind or
                       ((Ref_v.Kind = TbData or Ref_v.Kind = TbBc) and Act_v.Data /= Ref_v.Data) then
                        Mism_v := Mism_v + 1;
                        if Pos_v < 0 then
                            Pos_v := i;
                        end if;
                    end if;
                end loop;

                check_value(Mism_v, 0, error, msg & ": mismatches (first at " & to_string(Pos_v) & ")");
            end if;
        end procedure;

        procedure pushSeq (
            idx  : natural;
            n    : natural;
            seed : natural;
            bc   : boolean := true) is
        begin

            for i in 0 to n - 1 loop
                FarEnd_v.txPush(idx, seqChar(i, seed, bc));
            end loop;

        end procedure;

        -- Index of the first entry at or after first that is not a Null
        impure function firstNonNull (
            idx   : natural;
            first : natural) return natural is
        begin

            for i in first to FarEnd_v.rxCount(idx) - 1 loop
                if FarEnd_v.rxGet(idx, i).Kind /= TbNull then
                    return i;
                end if;
            end loop;

            return FarEnd_v.rxCount(idx);
        end function;

        procedure waitPortTxEmpty is
        begin

            while FarEnd_v.txCount(Port_c) > 0 loop
                wait until rising_edge(Clk);
            end loop;

        end procedure;

        -- Restarts the receiver: Receive Enable low, then high with the far end sending Nulls
        procedure restartRx is
        begin
            RxEnable <= '0';
            wait for 1 us;
            FarEnd_v.txClear(Far_c);
            FarEnd_v.setMode(Far_c, TbModeNull);
            RxEnable <= '1';
            await_value(Rx_GotNull, '1', 0 ns, 20 us, error, "gotNull after restart");
        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);

        while test_suite loop

            Rst <= '1';
            wait for 100 ns;
            wait until rising_edge(Clk);
            Rst <= '0';
            wait for 100 ns;

            if run("test_first_null") then
                -- TC-EN-01
                check_value(Spw_DOut, '0', error, "data after reset");
                check_value(Spw_SOut, '0', error, "strobe after reset");
                FarEnd_v.setLogNulls(Far_c, true);
                TxEnable <= '1';
                wait for 5 us;
                Edge_v   := FarEnd_v.edgeGet(Far_c, 0);
                check_value(Edge_v.D = '0' and Edge_v.S = '1', error, "first transition on the strobe line");
                Char_v   := FarEnd_v.rxGet(Far_c, 0);
                check_value(Char_v.Kind = TbNull, error, "first character is a Null");
                check_value(Char_v.T, Edge_v.T, error, "first Null starts with the first edge");
                -- Initial rate: 10 Mb/s at 100 MHz
                check_value(FarEnd_v.edgeGet(Far_c, 1).T - Edge_v.T, 100 ns, error, "initial bit period");
                check_value(FarEnd_v.rxErrors(Far_c), 0, error, "decoding errors");
                -- The first Null is sent even when another character is presented, which is not taken
                TxEnable <= '0';
                wait for 3 us;
                FarEnd_v.rxClear(Far_c);
                FarEnd_v.txPush(Port_c, tbChar(TbFct));
                Cnt_v    := TxAckCnt;
                TxEnable <= '1';
                wait for 1 us;
                check_value(TxAckCnt, Cnt_v + 1, error, "presented FCT taken once after the first Null");
                wait for 2 us;
                check_value(FarEnd_v.rxGet(Far_c, 0).Kind = TbNull, error, "first character after restart");
                check_value(FarEnd_v.rxGet(Far_c, 1).Kind = TbFct, error, "presented character follows");

            elsif run("test_tx_characters") then
                -- TC-EN-02
                -- A first Null is only detected when a control character follows it, as in the Started state
                FarEnd_v.setLogNulls(Far_c, true);
                TxEnable <= '1';
                wait for 3 us;
                check_value(FarEnd_v.rxGet(Far_c, 0).Kind = TbNull, error, "first Null");
                Start_v  := FarEnd_v.rxCount(Far_c);
                pushSeq(Port_c, 2000, 1);
                waitPortTxEmpty;
                wait for 5 us;
                checkSeq(Far_c, firstNonNull(Far_c, Start_v), 2000, 1, true, "transmitted sequence");
                check_value(FarEnd_v.rxErrors(Far_c), 0, error, "decoding errors");

            elsif run("test_tx_rates") then
                -- TC-EN-03
                TxEnable <= '1';
                wait for 3 us;
                TxRun    <= '1';

                FarEnd_v.setRxTimeout(Far_c, 10 us);

                for d in 0 to 3 loop

                    case d is
                        when 0 => Cfg_RunDiv <= x"01";
                        when 1 => Cfg_RunDiv <= x"02";
                        when 2 => Cfg_RunDiv <= x"07";
                        when others => Cfg_RunDiv <= x"FF";
                    end case;

                    FarEnd_v.setLogNulls(Far_c, true);
                    wait for 10 us;
                    FarEnd_v.rxClear(Far_c);
                    pushSeq(Port_c, 100, d + 10);
                    waitPortTxEmpty;
                    wait for 60 us;
                    -- Every edge one bit period after the previous one
                    Ok_v := true;

                    for i in 1 to minimum(FarEnd_v.edgeCount(Far_c), 8192) - 1 loop
                        T_v := FarEnd_v.edgeGet(Far_c, i).T - FarEnd_v.edgeGet(Far_c, i - 1).T;
                        if T_v /= to_integer(unsigned(Cfg_RunDiv)) * 10 ns then
                            Ok_v := false;
                        end if;
                    end loop;

                    check_value(Ok_v, error, "bit period " & to_string(to_integer(unsigned(Cfg_RunDiv))) & " cycles");
                    Start_v := firstNonNull(Far_c, 0);
                    checkSeq(Far_c, Start_v, 100, d + 10, true, "sequence at divider " &
                             to_string(to_integer(unsigned(Cfg_RunDiv))));
                    check_value(FarEnd_v.rxErrors(Far_c), 0, error, "decoding errors");
                end loop;

                -- Back to the initial rate outside Run
                TxRun <= '0';
                wait for 10 us;
                FarEnd_v.rxClear(Far_c);
                wait for 10 us;
                T_v   := FarEnd_v.edgeGet(Far_c, 5).T - FarEnd_v.edgeGet(Far_c, 4).T;
                check_value(T_v, 100 ns, error, "initial bit period outside Run");
                -- Rate change at bit boundaries: no edge closer than the smaller bit period
                TxRun      <= '1';
                Cfg_RunDiv <= x"03";
                FarEnd_v.rxClear(Far_c);

                for i in 0 to 20 loop
                    wait for 1.7 us;
                    TxRun <= not TxRun;
                end loop;

                Ok_v := true;

                for i in 1 to minimum(FarEnd_v.edgeCount(Far_c), 8192) - 1 loop
                    T_v := FarEnd_v.edgeGet(Far_c, i).T - FarEnd_v.edgeGet(Far_c, i - 1).T;
                    if T_v /= 30 ns and T_v /= 100 ns then
                        Ok_v := false;
                    end if;
                end loop;

                check_value(Ok_v, error, "bit periods during rate changes are 30 ns or 100 ns");
                check_value(FarEnd_v.rxErrors(Far_c), 0, error, "decoding errors");

            elsif run("test_tx_reset") then
                -- TC-EN-04
                Both_v := false;

                for k in 0 to 15 loop
                    FarEnd_v.rxClear(Far_c);
                    FarEnd_v.setLogNulls(Far_c, true);
                    pushSeq(Port_c, 50, k + 20);
                    TxEnable <= '1';
                    wait for 3 us + k * 37 ns;
                    wait until rising_edge(Clk);
                    TxEnable <= '0';
                    T_v      := now;
                    -- Edges caused by this clock edge belong to the time before the stop
                    wait for 1 ns;
                    Start_v := FarEnd_v.edgeCount(Far_c);
                    Prev_v  := FarEnd_v.edgeGet(Far_c, Start_v - 1);
                    wait for 3 us;
                    FarEnd_v.txClear(Port_c);
                    -- Edges after the stop: strobe reset first, then data one bit period (100 ns) later
                    Cnt_v := FarEnd_v.edgeCount(Far_c) - Start_v;
                    if Prev_v.D = '1' and Prev_v.S = '1' then
                        Both_v := true;
                        check_value(Cnt_v, 2, error, "two reset edges from D = S = '1'");
                        if Cnt_v = 2 then
                            Edge_v := FarEnd_v.edgeGet(Far_c, Start_v);
                            check_value(Edge_v.D = '1' and Edge_v.S = '0', error, "strobe reset first");
                            check_value(Edge_v.T - T_v <= 100 ns, error, "strobe reset at the next bit boundary");
                            check_value(FarEnd_v.edgeGet(Far_c, Start_v + 1).T - Edge_v.T, 100 ns, error,
                                        "delay between strobe and data reset");
                        end if;
                    elsif Prev_v.D = '1' or Prev_v.S = '1' then
                        check_value(Cnt_v, 1, error, "one reset edge");
                    else
                        check_value(Cnt_v, 0, error, "no reset edge");
                    end if;
                    Edge_v := FarEnd_v.edgeGet(Far_c, FarEnd_v.edgeCount(Far_c) - 1);
                    check_value(Edge_v.D = '0' and Edge_v.S = '0', error, "data and strobe reset");

                    for i in 1 to minimum(FarEnd_v.edgeCount(Far_c), 8192) - 1 loop
                        if FarEnd_v.edgeGet(Far_c, i).D /= FarEnd_v.edgeGet(Far_c, i - 1).D and
                           FarEnd_v.edgeGet(Far_c, i).S /= FarEnd_v.edgeGet(Far_c, i - 1).S then
                            alert(ERROR, "simultaneous transition of data and strobe");
                        end if;
                    end loop;

                end loop;

                check_value(Both_v, error, "a stop with data and strobe at '1' occurred");
                -- Restart: first edge on the strobe line, first character a Null
                FarEnd_v.rxClear(Far_c);
                TxEnable <= '1';
                wait for 3 us;
                Edge_v   := FarEnd_v.edgeGet(Far_c, 0);
                check_value(Edge_v.D = '0' and Edge_v.S = '1', error, "first transition after restart");
                check_value(FarEnd_v.rxGet(Far_c, 0).Kind = TbNull, error, "first character after restart");

            elsif run("test_null_detection") then
                -- TC-EN-10
                FarEnd_v.setLogNulls(Port_c, true);
                FarEnd_v.setBitPeriod(Far_c, 50 ns);
                FarEnd_v.setMode(Far_c, TbModeSilent);
                RxEnable <= '1';

                -- Characters without a Null are not passed and do not assert gotNull
                for i in 0 to 9 loop
                    FarEnd_v.txPush(Far_c, tbData(i * 3));
                    FarEnd_v.txPush(Far_c, tbChar(TbFct));
                end loop;

                tbWaitTxEmpty(Far_c);
                -- Each of the three parity bits of the Null sequence wrong: no detection
                FarEnd_v.txPush(Far_c, tbRaw("1111111111"));
                FarEnd_v.txPush(Far_c, tbRaw("111101000"));
                FarEnd_v.txPush(Far_c, tbRaw("1111111111"));
                FarEnd_v.txPush(Far_c, tbRaw("011111000"));
                FarEnd_v.txPush(Far_c, tbRaw("1111111111"));
                FarEnd_v.txPush(Far_c, tbRaw("011101001"));
                FarEnd_v.txPush(Far_c, tbRaw("1111111111"));
                tbWaitTxEmpty(Far_c);
                wait for 1 us;
                check_value(Rx_GotNull, '0', error, "no gotNull without a correct Null");
                check_value(FarEnd_v.rxCount(Port_c), 0, error, "no characters passed before gotNull");
                -- Correct sequence (the receiver is restarted, the pauses above caused disconnects)
                RxEnable <= '0';
                wait for 100 ns;
                RxEnable <= '1';
                FarEnd_v.txPush(Far_c, tbRaw("1111111111"));
                FarEnd_v.txPush(Far_c, tbRaw("011101000"));
                tbWaitTxEmpty(Far_c);
                wait for 200 ns;
                check_value(Rx_GotNull, '1', error, "gotNull on the Null sequence");
                -- gotNull is only cleared by Receive Enable
                FarEnd_v.setMode(Far_c, TbModeOff);
                wait for 3 us;
                check_value(Rx_GotNull, '1', error, "gotNull kept");
                RxEnable <= '0';
                wait for 100 ns;
                check_value(Rx_GotNull, '0', error, "gotNull cleared by Receive Enable");
                -- A Null after a data character with an odd number of ones has a parity bit of '1' and is
                -- not the first Null; the next one is
                FarEnd_v.setMode(Far_c, TbModeSilent);
                RxEnable <= '1';
                FarEnd_v.txPush(Far_c, tbData(16#01#));
                FarEnd_v.txPush(Far_c, tbChar(TbNull));
                FarEnd_v.txPush(Far_c, tbData(16#02#));
                tbWaitTxEmpty(Far_c);
                wait for 200 ns;
                check_value(Rx_GotNull, '0', error, "Null after an odd data character");
                FarEnd_v.txPush(Far_c, tbChar(TbNull));
                FarEnd_v.txPush(Far_c, tbChar(TbNull));
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                tbWaitTxEmpty(Far_c);
                wait for 200 ns;
                check_value(Rx_GotNull, '1', error, "gotNull on the next Null");
                check_value(FarEnd_v.rxCount(Port_c), 1, error, "characters after the first Null");
                if FarEnd_v.rxCount(Port_c) >= 1 then
                    check_value(FarEnd_v.rxGet(Port_c, 0).Kind = TbFct, error, "first FCT passed");
                end if;
                check_value(ParityErrCnt, 0, error, "no parity error");

            elsif run("test_rx_characters") then
                -- TC-EN-11
                FarEnd_v.setLogNulls(Port_c, true);
                FarEnd_v.setBitPeriod(Far_c, 20 ns);
                restartRx;
                pushSeq(Far_c, 3000, 2);
                tbWaitTxEmpty(Far_c);
                wait for 1 us;
                Start_v := firstNonNull(Port_c, 0);
                checkSeq(Port_c, Start_v, 3000, 2, true, "received sequence");
                check_value(ParityErrCnt + EscErrCnt + DisconnectCnt, 0, error, "no receive errors");
                -- Strict parity: the last character is passed after the parity bit of the next one
                FarEnd_v.setLogNulls(Port_c, false);
                FarEnd_v.setMode(Far_c, TbModeSilent);
                Cnt_v := FarEnd_v.rxCount(Port_c);
                FarEnd_v.txPush(Far_c, tbData(16#77#));
                tbWaitTxEmpty(Far_c);
                wait for 100 ns;
                check_value(FarEnd_v.rxCount(Port_c), Cnt_v, error, "character held until the next parity bit");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                tbWaitTxEmpty(Far_c);
                wait for 100 ns;
                check_value(FarEnd_v.rxCount(Port_c), Cnt_v + 1, error, "character passed after the parity check");

            elsif run("test_rx_parity") then
                -- TC-EN-12
                FarEnd_v.setLogNulls(Port_c, false);
                FarEnd_v.setBitPeriod(Far_c, 30 ns);
                Errs_v := 0;

                for k in 0 to 3 loop
                    restartRx;
                    Cnt_v := FarEnd_v.rxCount(Port_c);
                    FarEnd_v.txPush(Far_c, tbData(16#C3#));
                    FarEnd_v.txPush(Far_c, tbData(16#AA#));

                    case k is
                        when 0 => FarEnd_v.txPush(Far_c, tbChar(TbFct, x"00", true));
                        when 1 => FarEnd_v.txPush(Far_c, tbChar(TbData, x"5A", true));
                        when 2 => FarEnd_v.txPush(Far_c, tbChar(TbEop, x"00", true));
                        when others => FarEnd_v.txPush(Far_c, tbChar(TbBc, x"05", true));
                    end case;

                    FarEnd_v.txPush(Far_c, tbData(16#11#));
                    tbWaitTxEmpty(Far_c);
                    wait for 1 us;
                    Errs_v := Errs_v + 1;
                    check_value(ParityErrCnt, Errs_v, error, "parity error " & to_string(k));
                    -- 0xC3 is checked by the parity of 0xAA, 0xAA is not passed
                    check_value(FarEnd_v.rxCount(Port_c), Cnt_v + 1, error, "characters before the error");
                    check_value(FarEnd_v.rxGet(Port_c, Cnt_v).Data, x"C3", error, "last character passed");
                    check_value(DisconnectCnt + EscErrCnt, 0, error, "no further error after the parity error");
                end loop;

                -- Recovery after Receive Enable
                restartRx;
                Cnt_v := FarEnd_v.rxCount(Port_c);
                FarEnd_v.txPush(Far_c, tbData(16#99#));
                tbWaitTxEmpty(Far_c);
                wait for 1 us;
                check_value(FarEnd_v.rxGet(Port_c, Cnt_v).Data, x"99", error, "reception after restart");

            elsif run("test_rx_esc_error") then
                -- TC-EN-13
                FarEnd_v.setBitPeriod(Far_c, 30 ns);

                for k in 0 to 2 loop
                    restartRx;
                    Cnt_v := FarEnd_v.rxCount(Port_c);
                    FarEnd_v.txPush(Far_c, tbData(16#33#));
                    FarEnd_v.txPush(Far_c, tbChar(TbEsc));

                    case k is
                        when 0 => FarEnd_v.txPush(Far_c, tbChar(TbEsc));
                        when 1 => FarEnd_v.txPush(Far_c, tbChar(TbEop));
                        when others => FarEnd_v.txPush(Far_c, tbChar(TbEep));
                    end case;

                    FarEnd_v.txPush(Far_c, tbData(16#44#));
                    tbWaitTxEmpty(Far_c);
                    wait for 1 us;
                    check_value(EscErrCnt, k + 1, error, "ESC error " & to_string(k));
                    check_value(FarEnd_v.rxCount(Port_c), Cnt_v + 1, error, "characters before the ESC error");
                    check_value(FarEnd_v.rxGet(Port_c, Cnt_v).Data, x"33", error, "character before the ESC");
                end loop;

                check_value(ParityErrCnt + DisconnectCnt, 0, error, "no other error");

            elsif run("test_rx_disconnect") then
                -- TC-EN-14
                FarEnd_v.setBitPeriod(Far_c, 100 ns);
                -- Not enabled before the first edge
                RxEnable <= '1';
                wait for 10 us;
                check_value(DisconnectCnt, 0, error, "no disconnect before the first edge");

                for k in 0 to 4 loop
                    restartRx;
                    wait for 2 us + k * 13 ns;
                    FarEnd_v.setMode(Far_c, TbModeSilent);
                    wait for 3 us;
                    check_value(DisconnectCnt, k + 1, error, "disconnect " & to_string(k));
                    T_v := DisconnectT - FarEnd_v.getTxEdge(Far_c);
                    check_value(T_v > 727 ns and T_v <= 1 us, error,
                                "disconnect time " & to_string(T_v) & " in 727 ns to 1 us");
                end loop;

                -- Slowest rate allowed (2 Mb/s): no disconnect
                FarEnd_v.setBitPeriod(Far_c, 500 ns);
                restartRx;
                wait for 50 us;
                check_value(DisconnectCnt, 5, error, "no disconnect at 2 Mb/s");
                check_value(ParityErrCnt + EscErrCnt, 0, error, "no other error");

            elsif run("test_rx_simultaneous") then
                -- TC-EN-15
                FarEnd_v.setBitPeriod(Far_c, 40 ns);
                Errs_v := 0;

                for k in 0 to 19 loop
                    restartRx;
                    pushSeq(Far_c, 40, k + 30, false);
                    wait for 300 ns + k * 17 ns;
                    FarEnd_v.requestSimultaneous(Far_c);
                    wait for 4 us;
                    -- Two bits are lost: a later parity or ESC error, never a lock-up
                    check_value(ParityErrCnt + EscErrCnt > Errs_v, error, "error after simultaneous transition " &
                                to_string(k));
                    Errs_v := ParityErrCnt + EscErrCnt;
                    FarEnd_v.txClear(Far_c);
                end loop;

                -- The receiver works after re-enabling
                restartRx;
                Cnt_v := FarEnd_v.rxCount(Port_c);
                FarEnd_v.txPush(Far_c, tbData(16#5A#));
                tbWaitTxEmpty(Far_c);
                wait for 1 us;
                check_value(FarEnd_v.rxGet(Port_c, Cnt_v).Data, x"5A", error, "reception after simultaneous transitions");

            elsif run("test_rx_rates") then
                -- TC-EN-16
                FarEnd_v.setLogNulls(Port_c, true);

                for k in 0 to 4 loop

                    case k is
                        when 0 => FarEnd_v.setBitPeriod(Far_c, 12 ns);
                        when 1 => FarEnd_v.setBitPeriod(Far_c, 17 ns);
                        when 2 => FarEnd_v.setBitPeriod(Far_c, 100 ns);
                        when 3 => FarEnd_v.setBitPeriod(Far_c, 333 ns);
                        when others => FarEnd_v.setBitPeriod(Far_c, 500 ns);
                    end case;

                    FarEnd_v.rxClear(Port_c);
                    restartRx;
                    pushSeq(Far_c, 200, k + 40);
                    tbWaitTxEmpty(Far_c);
                    wait for 5 us;
                    Start_v := firstNonNull(Port_c, 0);
                    checkSeq(Port_c, Start_v, 200, k + 40, true, "bit period " &
                             to_string(FarEnd_v.getBitPeriod(Far_c)));
                end loop;

                check_value(ParityErrCnt + EscErrCnt + DisconnectCnt, 0, error, "no receive errors");

            elsif run("test_loopback") then
                -- TC-EN-17
                FarEnd_v.setLogNulls(Port_c, true);
                Cfg_Loopback <= '1';
                TxEnable     <= '1';
                RxEnable     <= '1';
                await_value(Rx_GotNull, '1', 0 ns, 10 us, error, "gotNull from the own transmitter");
                TxRun        <= '1';
                Cfg_RunDiv   <= x"04";
                wait for 2 us;
                Start_v      := FarEnd_v.rxCount(Port_c);
                pushSeq(Port_c, 500, 3);
                waitPortTxEmpty;
                wait for 2 us;
                checkSeq(Port_c, firstNonNull(Port_c, Start_v), 500, 3, true, "looped back sequence");
                check_value(ParityErrCnt + EscErrCnt + DisconnectCnt, 0, error, "no receive errors");
            end if;

        end loop;

        owrTestEnd(runner);
    end process;

    i_th : entity work.owr_enc_th
        port map (
            Clk           => Clk,
            Rst           => Rst,
            TxEnable      => TxEnable,
            RxEnable      => RxEnable,
            TxRun         => TxRun,
            Cfg_RunDiv    => Cfg_RunDiv,
            Cfg_Loopback  => Cfg_Loopback,
            Rx_GotNull    => Rx_GotNull,
            ParityErrCnt  => ParityErrCnt,
            EscErrCnt     => EscErrCnt,
            DisconnectCnt => DisconnectCnt,
            DisconnectT   => DisconnectT,
            TxAckCnt      => TxAckCnt,
            Spw_DOut      => Spw_DOut,
            Spw_SOut      => Spw_SOut
        );

end architecture;
