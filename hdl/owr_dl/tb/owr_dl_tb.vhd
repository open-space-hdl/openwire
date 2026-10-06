---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the Data Link layer: port A against the Data-Strobe far-end model (link state
-- machine, flow control, sending priority, broadcast codes, link error recovery) and ports A and B
-- back to back (traffic, back-pressure, restart, EDAC).
--
-- Documentation: hdl/owr_dl/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axistream;
    context bitvis_vip_axistream.vvc_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.owr_pkg.all;
    use work.owr_tb_pkg.all;
    use work.owr_tb_ds_pkg.all;
    use work.owr_dl_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_dl_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_dl_tb is

    signal LinkClk  : std_logic;
    signal UserClk  : std_logic;
    signal Rst      : std_logic := '1';
    signal CtrlA    : DlCtrl_t  := DlCtrlInit_c;
    signal CtrlB    : DlCtrl_t  := DlCtrlInit_c;
    signal StatA    : DlStat_t;
    signal StatB    : DlStat_t;
    signal LinkMode : std_logic := '0';
    signal Cut      : std_logic := '0';

begin

    test_runner_watchdog(runner, 100 ms);

    p_main : process is
        variable T_v     : time;
        variable T2_v    : time;
        variable Cnt_v   : natural;
        variable Start_v : natural;
        variable Fct_v   : natural;
        variable Char_v  : TbChar_t;
        variable Ok_v    : boolean;
        variable Cmd_v   : natural;
        variable Res_v   : bitvis_vip_axistream.vvc_cmd_pkg.t_vvc_result;

        -- Waits until port idx (0 = A, 1 = B) reaches a state
        procedure waitState (
            idx     : natural;
            state   : LinkState_t;
            timeout : time;
            msg     : string) is
            variable End_v : time;
            variable Cur_v : LinkState_t;
        begin
            End_v := now + timeout;

            loop
                if idx = 0 then
                    Cur_v := StatA.State;
                else
                    Cur_v := StatB.State;
                end if;
                exit when Cur_v = state or now >= End_v;
                wait until rising_edge(LinkClk);
            end loop;

            check_value(Cur_v = state, error, msg & ": state " & stateStr(state) & " reached (is " & stateStr(Cur_v) &
                        ")");
        end procedure;

        -- Port A with LinkStart against the far end sending Nulls and fcts FCTs: Run
        procedure bringUp (fcts : natural) is
        begin
            CtrlA.LinkStart <= '1';
            FarEnd_v.setBitPeriod(Far_c, 100 ns);
            FarEnd_v.setMode(Far_c, TbModeNull);
            waitState(0, StateConnecting_c, 50 us, "bring-up");

            for i in 1 to fcts loop
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
            end loop;

            waitState(0, StateRun_c, 20 us, "bring-up");
        end procedure;

        -- Far end sends a packet of n data characters (values (first + i) mod 256) and a marker
        procedure farPacket (
            n      : natural;
            first  : natural;
            marker : TbCharKind_t) is
        begin

            for i in 0 to n - 1 loop
                FarEnd_v.txPush(Far_c, tbData(first + i));
            end loop;

            if marker = TbEop or marker = TbEep then
                FarEnd_v.txPush(Far_c, tbChar(marker));
            end if;
        end procedure;

        -- Number of N-Chars of port A received by the far end from log entry first
        impure function farNChars (first : natural := 0) return natural is
        begin
            return tbRxCountKind(Far_c, TbData, first) + tbRxCountKind(Far_c, TbEop, first) +
                   tbRxCountKind(Far_c, TbEep, first);
        end function;

        -- Checks the N-Chars of port A received by the far end from log entry first: n data characters with the
        -- values (dfirst + i) mod 256, followed by a marker (or no marker for TbNull)
        procedure checkFarPacket (
            first  : natural;
            n      : natural;
            dfirst : natural;
            marker : TbCharKind_t;
            msg    : string) is
            variable Idx_v  : natural;
            variable Mism_v : natural := 0;
            variable Got_v  : TbChar_t;
        begin
            Idx_v := first;

            for i in 0 to n - 1 loop

                -- Skip everything that is not an N-Char
                while Idx_v < FarEnd_v.rxCount(Far_c) and FarEnd_v.rxGet(Far_c, Idx_v).Kind /= TbData and
                      FarEnd_v.rxGet(Far_c, Idx_v).Kind /= TbEop and FarEnd_v.rxGet(Far_c, Idx_v).Kind /= TbEep loop
                    Idx_v := Idx_v + 1;
                end loop;

                if Idx_v >= FarEnd_v.rxCount(Far_c) then
                    alert(ERROR, msg & ": only " & to_string(i) & " of " & to_string(n) & " data characters");
                    return;
                end if;
                Got_v := FarEnd_v.rxGet(Far_c, Idx_v);
                if Got_v.Kind /= TbData or to_integer(unsigned(Got_v.Data)) /= (dfirst + i) mod 256 then
                    Mism_v := Mism_v + 1;
                end if;
                Idx_v := Idx_v + 1;
            end loop;

            check_value(Mism_v, 0, error, msg & ": data mismatches");
            if marker /= TbNull then

                while Idx_v < FarEnd_v.rxCount(Far_c) and FarEnd_v.rxGet(Far_c, Idx_v).Kind /= TbData and
                      FarEnd_v.rxGet(Far_c, Idx_v).Kind /= TbEop and FarEnd_v.rxGet(Far_c, Idx_v).Kind /= TbEep loop
                    Idx_v := Idx_v + 1;
                end loop;

                check_value(Idx_v < FarEnd_v.rxCount(Far_c) and FarEnd_v.rxGet(Far_c, Idx_v).Kind = marker, error,
                            msg & ": end of packet marker " & tbKindStr(marker));
            end if;
        end procedure;

        procedure pulseCtrl (signal ctrl : out std_logic) is
        begin
            wait until rising_edge(LinkClk);
            ctrl <= '1';
            wait until rising_edge(LinkClk);
            ctrl <= '0';
        end procedure;

        -- Broadcast code request of port A, valid for one clock cycle
        procedure bcRequest (data : std_logic_vector(7 downto 0)) is
        begin
            wait until rising_edge(LinkClk);
            CtrlA.TxBcData  <= data;
            CtrlA.TxBcValid <= '1';
            wait until rising_edge(LinkClk);
            CtrlA.TxBcValid <= '0';
        end procedure;

        -- Waits until the far end has decoded one more Null, then waits t (inside the next character of A)
        procedure syncFarNull (t : time) is
            variable N_v : natural;
        begin
            N_v := FarEnd_v.rxKindCount(Far_c, TbNull);

            while FarEnd_v.rxKindCount(Far_c, TbNull) = N_v loop
                wait for 10 ns;
            end loop;

            wait for t;
        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);

        for i in VvcATx_c to VvcBRx_c loop
            disable_log_msg(AXISTREAM_VVCT, i, ALL_MESSAGES);
        end loop;

        while test_suite loop

            Rst <= '1';
            wait for 100 ns;
            wait until rising_edge(LinkClk);
            Rst <= '0';
            T_v := now;

            if run("test_lsm_startup") then
                -- TC-DL-01
                CtrlA.LinkStart <= '1';
                FarEnd_v.setLogNulls(Far_c, true);
                -- ErrorReset 6.4 us, ErrorWait 12.8 us
                waitState(0, StateErrorWait_c, 10 us, "after reset");
                T2_v := now - T_v;
                check_value(T2_v >= 5.82 us and T2_v <= 7.22 us, error, "ErrorReset duration " & to_string(T2_v));
                T_v  := now;
                waitState(0, StateReady_c, 20 us, "after ErrorWait");
                T2_v := now - T_v;
                check_value(T2_v >= 11.64 us and T2_v <= 14.33 us, error, "ErrorWait duration " & to_string(T2_v));
                -- LinkStart: Started at once; without far end a timeout after 12.8 us
                wait until rising_edge(LinkClk);
                wait until rising_edge(LinkClk);
                check_value(StatA.State = StateStarted_c, error, "Started on LinkStart");
                T_v := now;
                waitState(0, StateErrorReset_c, 20 us, "Started timeout");
                -- Far end sends Nulls: Connecting, A sends seven FCTs (64 N-Chars of room), then Run on an FCT
                FarEnd_v.setMode(Far_c, TbModeNull);
                waitState(0, StateStarted_c, 30 us, "restart");
                Start_v := FarEnd_v.rxCount(Far_c);
                waitState(0, StateConnecting_c, 10 us, "gotNull and Null sent");
                -- In Started only Nulls were sent
                check_value(FarEnd_v.rxCount(Far_c) - tbRxCountKind(Far_c, TbNull, Start_v) - Start_v, 0, error,
                            "only Nulls in Started");
                wait for 10 us;
                check_value(tbRxCountKind(Far_c, TbFct), 7, error, "FCTs sent in Connecting");
                check_value(farNChars, 0, error, "no N-Char before Run");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "FCT received");
                wait for 1 us;
                check_value(StatA.TxCredit, 8, error, "transmit credit after one FCT");
                check_value(StatA.RxCredit, 56, error, "receive credit after seven FCTs");
                check_value(StatA.CntRun, 1, error, "Run entered once");
                check_value(FarEnd_v.rxErrors(Far_c), 0, error, "no decoding errors at the far end");

            elsif run("test_lsm_autostart") then
                -- TC-DL-02
                CtrlA.AutoStart <= '1';
                waitState(0, StateReady_c, 30 us, "after reset");
                wait for 50 us;
                check_value(StatA.State = StateReady_c, error, "AutoStart waits in Ready without a Null");
                FarEnd_v.setBitPeriod(Far_c, 100 ns);
                FarEnd_v.setMode(Far_c, TbModeNull);
                waitState(0, StateStarted_c, 5 us, "AutoStart and gotNull");
                waitState(0, StateConnecting_c, 5 us, "Connecting");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "Run");

            elsif run("test_lsm_disabled") then
                -- TC-DL-03
                CtrlA.LinkDisabled <= '1';
                CtrlA.LinkStart    <= '1';
                FarEnd_v.setBitPeriod(Far_c, 100 ns);
                FarEnd_v.setMode(Far_c, TbModeNull);
                wait for 40 us;
                check_value(StatA.State = StateErrorReset_c, error, "LinkDisabled keeps ErrorReset");
                check_value(StatA.GotNull, '0', error, "receiver disabled in ErrorReset");
                CtrlA.LinkDisabled <= '0';
                waitState(0, StateConnecting_c, 40 us, "enabled");
                -- LinkDisabled in Connecting
                CtrlA.LinkDisabled <= '1';
                wait until rising_edge(LinkClk);
                wait until rising_edge(LinkClk);
                wait until rising_edge(LinkClk);
                check_value(StatA.State = StateErrorReset_c, error, "LinkDisabled in Connecting");
                check_value(StatA.CntRecovery, 0, error, "no recovery outside Run");
                CtrlA.LinkDisabled <= '0';
                waitState(0, StateConnecting_c, 40 us, "enabled again");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "Run");
                -- LinkDisabled in Run: ErrorReset and recovery with the cause
                CtrlA.LinkDisabled <= '1';
                wait until rising_edge(LinkClk);
                wait until rising_edge(LinkClk);
                wait until rising_edge(LinkClk);
                check_value(StatA.State = StateErrorReset_c, error, "LinkDisabled in Run");
                wait for 1 us;
                check_value(StatA.CntRecovery, 1, error, "recovery after LinkDisabled in Run");
                check_value(StatA.Cause, CauseLinkDisabled_c, error, "cause LinkDisabled");
                check_value(StatA.Recovery, '0', error, "recovery complete");
                -- LinkDisabled in ErrorWait and Ready
                CtrlA.LinkStart    <= '0';
                CtrlA.LinkDisabled <= '0';
                waitState(0, StateErrorWait_c, 10 us, "ErrorWait");
                CtrlA.LinkDisabled <= '1';
                wait for 50 ns;
                check_value(StatA.State = StateErrorReset_c, error, "LinkDisabled in ErrorWait");
                CtrlA.LinkDisabled <= '0';
                waitState(0, StateReady_c, 30 us, "Ready");
                CtrlA.LinkDisabled <= '1';
                wait for 50 ns;
                check_value(StatA.State = StateErrorReset_c, error, "LinkDisabled in Ready");
                -- LinkDisabled in Started
                CtrlA.LinkDisabled <= '0';
                FarEnd_v.setMode(Far_c, TbModeOff);
                CtrlA.LinkStart    <= '1';
                waitState(0, StateStarted_c, 30 us, "Started");
                CtrlA.LinkDisabled <= '1';
                wait for 50 ns;
                check_value(StatA.State = StateErrorReset_c, error, "LinkDisabled in Started");

            elsif run("test_lsm_timeouts") then
                -- TC-DL-04
                CtrlA.LinkStart <= '1';
                waitState(0, StateStarted_c, 30 us, "Started");
                T_v             := now;
                waitState(0, StateErrorReset_c, 20 us, "Started timeout");
                T2_v            := now - T_v;
                check_value(T2_v >= 11.64 us and T2_v <= 14.33 us, error, "Started timeout " & to_string(T2_v));
                -- Connecting without FCT
                FarEnd_v.setBitPeriod(Far_c, 100 ns);
                FarEnd_v.setMode(Far_c, TbModeNull);
                waitState(0, StateConnecting_c, 30 us, "Connecting");
                T_v  := now;
                waitState(0, StateErrorReset_c, 20 us, "Connecting timeout");
                T2_v := now - T_v;
                check_value(T2_v >= 11.64 us and T2_v <= 14.33 us, error, "Connecting timeout " & to_string(T2_v));
                check_value(StatA.CntRun, 0, error, "no Run without FCT");

            elsif run("test_lsm_errors") then
                -- TC-DL-05
                FarEnd_v.setBitPeriod(Far_c, 100 ns);
                FarEnd_v.setMode(Far_c, TbModeNull);

                -- FCT, N-Char and broadcast code received in ErrorWait and Ready: ErrorReset
                for k in 0 to 5 loop
                    if k < 3 then
                        waitState(0, StateErrorWait_c, 30 us, "ErrorWait " & to_string(k));
                    else
                        waitState(0, StateReady_c, 30 us, "Ready " & to_string(k));
                    end if;
                    wait for 2 us;
                    Cnt_v := StatA.CntRun;

                    case k mod 3 is
                        when 0 => FarEnd_v.txPush(Far_c, tbChar(TbFct));
                        when 1 => FarEnd_v.txPush(Far_c, tbData(16#3A#));
                        when others => FarEnd_v.txPush(Far_c, tbTimeCode(5));
                    end case;

                    FarEnd_v.txPush(Far_c, tbChar(TbNull));
                    waitState(0, StateErrorReset_c, 5 us, "received character " & to_string(k));
                end loop;

                -- Parity error, ESC error and disconnect in Ready
                for k in 0 to 2 loop
                    waitState(0, StateReady_c, 30 us, "Ready for error " & to_string(k));
                    wait for 1 us;

                    case k is
                        when 0 =>
                            FarEnd_v.txPush(Far_c, tbChar(TbNull, x"00", true));
                        when 1 =>
                            FarEnd_v.txPush(Far_c, tbChar(TbEsc));
                            FarEnd_v.txPush(Far_c, tbChar(TbEop));
                        when others =>
                            FarEnd_v.setMode(Far_c, TbModeSilent);
                    end case;

                    waitState(0, StateErrorReset_c, 5 us, "error " & to_string(k));
                    FarEnd_v.setMode(Far_c, TbModeNull);
                end loop;

                check_value(StatA.CntParity, 1, error, "parity error counted");
                check_value(StatA.CntEsc, 1, error, "ESC error counted");
                check_value(StatA.CntDisc, 1, error, "disconnect counted");
                -- N-Char and broadcast code in Connecting; disconnect in Connecting
                CtrlA.LinkStart <= '1';

                for k in 0 to 2 loop
                    waitState(0, StateConnecting_c, 40 us, "Connecting " & to_string(k));

                    case k is
                        when 0 => FarEnd_v.txPush(Far_c, tbData(16#11#));
                        when 1 => FarEnd_v.txPush(Far_c, tbInterrupt(3));
                        when others => FarEnd_v.setMode(Far_c, TbModeSilent);
                    end case;

                    FarEnd_v.txPush(Far_c, tbChar(TbNull));
                    waitState(0, StateErrorReset_c, 5 us, "Connecting exit " & to_string(k));
                    check_value(StatA.RxLevel, 0, error, "no N-Char stored outside Run");
                    check_value(StatA.CntRxBc, 0, error, "no broadcast code passed outside Run");
                    FarEnd_v.setMode(Far_c, TbModeNull);
                end loop;

                check_value(StatA.CntRun, 0, error, "no Run");
                -- Parity error and disconnect in Run: ErrorReset and recovery
                waitState(0, StateConnecting_c, 40 us, "Connecting");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "Run");
                FarEnd_v.txPush(Far_c, tbChar(TbFct, x"00", true));
                waitState(0, StateErrorReset_c, 5 us, "parity error in Run");
                wait for 1 us;
                check_value(StatA.Cause, CauseParity_c, error, "cause parity error");
                waitState(0, StateConnecting_c, 40 us, "Connecting");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "Run");
                FarEnd_v.txPush(Far_c, tbChar(TbEsc));
                FarEnd_v.txPush(Far_c, tbChar(TbEsc));
                waitState(0, StateErrorReset_c, 5 us, "ESC error in Run");
                wait for 1 us;
                check_value(StatA.Cause, CauseEsc_c, error, "cause ESC error");
                waitState(0, StateConnecting_c, 40 us, "Connecting");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "Run");
                FarEnd_v.setMode(Far_c, TbModeSilent);
                waitState(0, StateErrorReset_c, 5 us, "disconnect in Run");
                wait for 1 us;
                check_value(StatA.Cause, CauseDisconnect_c, error, "cause disconnect");
                check_value(StatA.CntRecovery, 3, error, "recoveries");

            elsif run("test_port_reset") then
                -- TC-DL-06
                bringUp(1);
                -- 20 data characters: 8 sent with the credit, the rest stays in the transmit FIFO
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(20), "packet");
                -- 10 data characters received and not read
                farPacket(10, 0, TbNull);
                wait for 30 us;
                check_value(StatA.TxLevel, 13, error, "transmit FIFO level");
                check_value(StatA.RxLevel, 10, error, "receive FIFO level");
                pulseCtrl(CtrlA.PortReset);
                wait until rising_edge(LinkClk);
                check_value(StatA.State = StateErrorReset_c, error, "ErrorReset after port reset");
                wait for 1 us;
                check_value(StatA.TxLevel, 0, error, "transmit FIFO cleared");
                check_value(StatA.RxLevel, 0, error, "receive FIFO cleared");
                check_value(StatA.Recovery, '0', error, "recovery state Normal");
                check_value(StatA.TxCredit + StatA.RxCredit, 0, error, "credits zero");
                -- The link starts again
                FarEnd_v.txClear(Far_c);
                waitState(0, StateConnecting_c, 40 us, "restart");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "Run after port reset");
                -- Port reset during a recovery that waits for the end of a packet: Normal at once
                await_completion(AXISTREAM_VVCT, VvcATx_c, 100 us, "first packet written");
                shared_axistream_vvc_config(VvcATx_c).bfm_config.valid_low_at_word_num := 30;
                shared_axistream_vvc_config(VvcATx_c).bfm_config.valid_low_duration    := 5000;
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(60), "packet with a pause");
                wait for 20 us;
                FarEnd_v.setMode(Far_c, TbModeSilent);
                waitState(0, StateErrorReset_c, 5 us, "disconnect");
                wait for 2 us;
                check_value(StatA.Recovery, '1', error, "recovery waits for the end of the packet");
                check_value(StatA.Spill, '1', error, "packet remainder being discarded");
                pulseCtrl(CtrlA.PortReset);
                wait until rising_edge(LinkClk);
                wait until rising_edge(LinkClk);
                check_value(StatA.Recovery, '0', error, "recovery Normal after port reset");
                check_value(StatA.Spill, '0', error, "discard stopped by port reset");
                await_completion(AXISTREAM_VVCT, VvcATx_c, 200 us, "packet written");

            elsif run("test_fc_rx_credit") then
                -- TC-DL-10
                bringUp(1);
                wait for 2 us;
                Fct_v := tbRxCountKind(Far_c, TbFct);
                check_value(Fct_v, 7, error, "seven FCTs for a FIFO of 64");
                -- 8 N-Chars received and not read: no further FCT
                farPacket(7, 0, TbEop);
                wait for 15 us;
                check_value(StatA.RxCredit, 48, error, "receive credit after 8 N-Chars");
                check_value(StatA.RxLevel, 8, error, "receive FIFO level");
                check_value(tbRxCountKind(Far_c, TbFct), Fct_v, error, "no FCT without room");
                -- Reading the packet makes room for one FCT
                axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(7), "packet");
                await_completion(AXISTREAM_VVCT, VvcARx_c, 50 us, "packet read");
                wait for 3 us;
                check_value(tbRxCountKind(Far_c, TbFct), Fct_v + 1, error, "one FCT after reading 8 N-Chars");
                check_value(StatA.RxCredit, 56, error, "receive credit 56");
                -- The full credit received without reading: no FCT while the FIFO has no room for 8 more
                Fct_v := tbRxCountKind(Far_c, TbFct);
                farPacket(55, 0, TbEop);
                wait for 70 us;
                check_value(StatA.RxCredit, 0, error, "receive credit used");
                check_value(StatA.RxLevel, 56, error, "receive FIFO level 56");
                check_value(tbRxCountKind(Far_c, TbFct), Fct_v, error, "no FCT with 8 places left");
                check_value(StatA.CntCredit, 0, error, "no credit error");
                axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(55), "packet of 55");
                await_completion(AXISTREAM_VVCT, VvcARx_c, 50 us, "packet read");
                wait for 10 us;
                check_value(tbRxCountKind(Far_c, TbFct), Fct_v + 7, error, "seven FCTs after reading");

            elsif run("test_fc_tx_credit") then
                -- TC-DL-11
                bringUp(1);
                Start_v := FarEnd_v.rxCount(Far_c);
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(40, 5), "packet of 40");
                wait for 30 us;
                check_value(farNChars(Start_v), 8, error, "eight N-Chars with one FCT");
                check_value(StatA.TxCredit, 0, error, "transmit credit used");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                wait for 30 us;
                check_value(farNChars(Start_v), 24, error, "16 more N-Chars with two FCTs");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                wait for 30 us;
                check_value(farNChars(Start_v), 41, error, "whole packet with its EOP");
                checkFarPacket(Start_v, 40, 5, TbEop, "packet at the far end");
                check_value(StatA.TxCredit, 48 - 41, error, "remaining transmit credit");

            elsif run("test_fc_credit_errors") then
                -- TC-DL-12
                bringUp(1);

                -- Seven more FCTs after one: 64 > 56
                for i in 1 to 6 loop
                    FarEnd_v.txPush(Far_c, tbChar(TbFct));
                end loop;

                wait for 10 us;
                check_value(StatA.TxCredit, 56, error, "transmit credit 56");
                check_value(StatA.State = StateRun_c, error, "Run with 56");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateErrorReset_c, 5 us, "credit error on FCT");
                wait for 1 us;
                check_value(StatA.CntCredit, 1, error, "credit error counted");
                check_value(StatA.Cause, CauseCredit_c, error, "cause credit error");
                -- One N-Char more than the credit: credit error, the N-Char is not stored, EEP after the data
                FarEnd_v.txClear(Far_c);
                waitState(0, StateConnecting_c, 40 us, "Connecting");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "Run");
                wait for 3 us;
                farPacket(57, 0, TbNull);
                waitState(0, StateErrorReset_c, 80 us, "credit error on N-Char");
                wait for 1 us;
                check_value(StatA.CntCredit, 2, error, "second credit error");
                check_value(StatA.RxLevel, 57, error, "56 data characters and an EEP");
                axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(56, 0, true), "56 data and EEP");
                await_completion(AXISTREAM_VVCT, VvcARx_c, 50 us, "packet read");

            elsif run("test_tx_priority") then
                -- TC-DL-20
                CtrlA.RunDiv <= std_logic_vector(to_unsigned(20, 8));
                bringUp(1);
                -- Use the transmit credit, then receive 8 N-Chars that are not read yet
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(7), "first packet");
                farPacket(7, 0, TbEop);
                wait for 40 us;
                check_value(StatA.TxCredit, 0, error, "no transmit credit");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                wait for 3 us;
                check_value(StatA.TxCredit, 8, error, "transmit credit");
                -- Inside a Null of A: request a broadcast code, read the packet (FCT request) and queue N-Chars
                Start_v := FarEnd_v.rxCount(Far_c);
                syncFarNull(400 ns);
                bcRequest(x"07");
                axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(7), "packet");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(3, 9), "second packet");
                wait for 30 us;
                -- Order: broadcast code, FCT, N-Chars
                Char_v := FarEnd_v.rxGet(Far_c, Start_v);
                check_value(Char_v.Kind = TbBc and Char_v.Data = x"07", error, "broadcast code first (" &
                            tbKindStr(Char_v.Kind) & ")");
                Char_v := FarEnd_v.rxGet(Far_c, Start_v + 1);
                check_value(Char_v.Kind = TbFct, error, "FCT second (" & tbKindStr(Char_v.Kind) & ")");
                checkFarPacket(Start_v + 2, 3, 9, TbEop, "N-Chars last");

            elsif run("test_bc_service") then
                -- TC-DL-21
                -- Broadcast codes outside Run are discarded
                CtrlA.LinkStart <= '1';
                waitState(0, StateStarted_c, 30 us, "Started");
                bcRequest(x"21");
                wait until rising_edge(LinkClk);
                check_value(StatA.CntBcDisc, 1, error, "broadcast code discarded outside Run");
                FarEnd_v.setBitPeriod(Far_c, 100 ns);
                FarEnd_v.setMode(Far_c, TbModeNull);
                waitState(0, StateConnecting_c, 40 us, "Connecting");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "Run");
                Start_v         := FarEnd_v.rxCount(Far_c);

                -- In Run: sent at once
                for i in 0 to 3 loop
                    bcRequest(std_logic_vector(to_unsigned(16#40# + i, 8)));
                    wait for 500 ns;
                end loop;

                wait for 10 us;
                check_value(tbRxCountKind(Far_c, TbBc, Start_v), 4, error, "broadcast codes sent in Run");
                check_value(tbRxCountKind(Far_c, TbBc), 4, error, "discarded code never sent");

                -- The last broadcast code in the log (FCTs may lie between them)
                for i in Start_v to FarEnd_v.rxCount(Far_c) - 1 loop
                    if FarEnd_v.rxGet(Far_c, i).Kind = TbBc then
                        Char_v := FarEnd_v.rxGet(Far_c, i);
                    end if;
                end loop;

                check_value(Char_v.Data, x"43", error, "last broadcast code");
                -- Received broadcast codes are passed in Run
                FarEnd_v.txPush(Far_c, tbTimeCode(12));
                FarEnd_v.txPush(Far_c, tbInterrupt(31));
                wait for 5 us;
                check_value(StatA.CntRxBc, 2, error, "received broadcast codes");
                check_value(FarEnd_v.rxGet(BcLogA_c, 0).Data, x"0C", error, "time-code value");
                check_value(FarEnd_v.rxGet(BcLogA_c, 1).Data, x"9F", error, "interrupt code value");
                -- A waiting code is discarded in ErrorReset: 1 us bit period, request inside a Null, then LinkDisabled
                CtrlA.RunDiv       <= std_logic_vector(to_unsigned(100, 8));
                wait for 20 us;
                syncFarNull(1.5 us);
                bcRequest(x"55");
                wait for 100 ns;
                check_value(StatA.TxBcReady, '0', error, "broadcast code waiting in the slot");
                CtrlA.LinkDisabled <= '1';
                wait for 1 us;
                CtrlA.LinkDisabled <= '0';
                waitState(0, StateConnecting_c, 40 us, "restart");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "Run");
                wait for 50 us;
                check_value(tbRxCountKind(Far_c, TbBc), 4, error, "waiting code discarded in ErrorReset");

            elsif run("test_rec_tx_discard") then
                -- TC-DL-30
                bringUp(1);
                Start_v := FarEnd_v.rxCount(Far_c);
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(100), "long packet");
                wait for 30 us;
                check_value(farNChars(Start_v), 8, error, "eight data characters sent");
                -- Disconnect in the middle of the packet
                FarEnd_v.setMode(Far_c, TbModeSilent);
                waitState(0, StateErrorReset_c, 5 us, "disconnect");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(10, 200), "next packet");
                await_completion(AXISTREAM_VVCT, VvcATx_c, 100 us, "packets written");
                wait for 2 us;
                check_value(StatA.Recovery, '0', error, "recovery complete");
                check_value(StatA.Cause, CauseDisconnect_c, error, "cause disconnect");
                check_value(StatA.TxLevel, 11, error, "only the next packet in the transmit FIFO");
                -- After the restart the next packet is sent complete
                FarEnd_v.setMode(Far_c, TbModeNull);
                waitState(0, StateConnecting_c, 40 us, "restart");
                Start_v := FarEnd_v.rxCount(Far_c);
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "Run");
                wait for 10 us;
                check_value(farNChars(Start_v), 11, error, "N-Chars after the restart");
                checkFarPacket(Start_v, 10, 200, TbEop, "next packet");

            elsif run("test_rec_rx_eep") then
                -- TC-DL-31
                bringUp(1);
                -- Parity error after 10 data characters: the 10th is not confirmed by a correct parity bit, so 9 data
                -- characters and an EEP are received
                farPacket(10, 50, TbNull);
                FarEnd_v.txPush(Far_c, tbChar(TbData, x"AA", true));
                waitState(0, StateErrorReset_c, 20 us, "parity error");
                axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(9, 50, true), "9 data and EEP");
                await_completion(AXISTREAM_VVCT, VvcARx_c, 50 us, "packet read");
                check_value(StatA.Cause, CauseParity_c, error, "cause parity");
                -- Error after a complete packet: no EEP
                FarEnd_v.txClear(Far_c);
                waitState(0, StateConnecting_c, 40 us, "restart");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(0, StateRun_c, 5 us, "Run");
                farPacket(5, 70, TbEop);
                FarEnd_v.txPush(Far_c, tbChar(TbEsc));
                FarEnd_v.txPush(Far_c, tbChar(TbEep));
                waitState(0, StateErrorReset_c, 20 us, "ESC error");
                wait for 2 us;
                check_value(StatA.RxLevel, 6, error, "no EEP after a complete packet");
                check_value(StatA.Cause, CauseEsc_c, error, "cause ESC");
                axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(5, 70), "complete packet");
                await_completion(AXISTREAM_VVCT, VvcARx_c, 50 us, "packet read");

            elsif run("test_link_traffic") then
                -- TC-DL-40
                LinkMode        <= '1';
                CtrlA.LinkStart <= '1';
                CtrlB.LinkStart <= '1';
                waitState(0, StateRun_c, 60 us, "A");
                waitState(1, StateRun_c, 60 us, "B");

                -- Packets of 0 to 300 bytes in both directions, EOP and EEP
                for i in 0 to 59 loop
                    axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket((i * 37) mod 301, i, i mod 7 = 3),
                                       "A to B " & to_string(i));
                    axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket((i * 37) mod 301, i, i mod 7 = 3),
                                     "A to B " & to_string(i));
                    axistream_transmit(AXISTREAM_VVCT, VvcBTx_c, owrCountPacket((i * 53) mod 301, i + 7, false),
                                       "B to A " & to_string(i));
                    axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket((i * 53) mod 301, i + 7, false),
                                     "B to A " & to_string(i));
                end loop;

                await_completion(AXISTREAM_VVCT, VvcBRx_c, 20 ms, "A to B received");
                await_completion(AXISTREAM_VVCT, VvcARx_c, 20 ms, "B to A received");
                -- Throughput of 20 packets of 1000 bytes at 100 Mb/s: data characters of 10 bits, EOP of 4 bits
                T_v := now;

                for i in 0 to 19 loop
                    axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(1000, i), "long " & to_string(i));
                    axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(1000, i), "long " & to_string(i));
                end loop;

                await_completion(AXISTREAM_VVCT, VvcBRx_c, 20 ms, "long packets received");
                T2_v := now - T_v;
                log(ID_SEQUENCER, "20000 bytes in " & to_string(T2_v) & ": " &
                    to_string(20000.0 * 8.0 / real(T2_v / 1 ns) * 1000.0) & " Mb/s user data");
                check_value(T2_v < 20000 * 10 * 10 ns * 105 / 100, error, "throughput at least 95 % of 8 Mb/s per 10 Mb/s");
                check_value(StatA.CntRun + StatB.CntRun, 2, error, "no link restart");
                check_value(StatA.CntCredit + StatB.CntCredit + StatA.CntOverflow + StatB.CntOverflow, 0, error,
                            "no credit error or overflow");

            elsif run("test_link_backpressure") then
                -- TC-DL-41
                LinkMode                                                                        <= '1';
                CtrlA.LinkStart                                                                 <= '1';
                CtrlB.LinkStart                                                                 <= '1';
                waitState(0, StateRun_c, 60 us, "A");
                waitState(1, StateRun_c, 60 us, "B");
                shared_axistream_vvc_config(VvcBRx_c).bfm_config.ready_low_at_word_num          := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(VvcBRx_c).bfm_config.ready_low_duration             := C_RANDOM;
                shared_axistream_vvc_config(VvcBRx_c).bfm_config.ready_low_max_random_duration  := 40;
                shared_axistream_vvc_config(VvcBRx_c).bfm_config.ready_low_multiple_random_prob := 0.2;
                shared_axistream_vvc_config(VvcATx_c).bfm_config.valid_low_at_word_num          := C_MULTIPLE_RANDOM;
                shared_axistream_vvc_config(VvcATx_c).bfm_config.valid_low_duration             := C_RANDOM;
                shared_axistream_vvc_config(VvcATx_c).bfm_config.valid_low_max_random_duration  := 20;
                shared_axistream_vvc_config(VvcATx_c).bfm_config.valid_low_multiple_random_prob := 0.1;

                for i in 0 to 49 loop
                    axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket((i * 71) mod 200 + 1, i),
                                       "A to B " & to_string(i));
                    axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket((i * 71) mod 200 + 1, i),
                                     "A to B " & to_string(i));
                end loop;

                await_completion(AXISTREAM_VVCT, VvcBRx_c, 20 ms, "received with back-pressure");
                check_value(StatA.CntRun + StatB.CntRun, 2, error, "no link restart");

            elsif run("test_link_restart") then
                -- TC-DL-42
                LinkMode        <= '1';
                CtrlA.LinkStart <= '1';
                CtrlB.LinkStart <= '1';
                waitState(0, StateRun_c, 60 us, "A");
                waitState(1, StateRun_c, 60 us, "B");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(200, 0), "packet 0");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(200, 1), "packet 1");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(200, 2), "packet 2");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(200, 3), "packet 3");
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(200, 0), "packet 0");
                axistream_receive(AXISTREAM_VVCT, VvcBRx_c, "packet 1 (truncated)");
                Cmd_v           := get_last_received_cmd_idx(AXISTREAM_VVCT, VvcBRx_c);
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(200, 2), "packet 2");
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(200, 3), "packet 3");
                -- Cut the line in the middle of packet 1
                wait for 30 us;
                Cut <= '1';
                wait for 3 us;
                Cut <= '0';
                await_completion(AXISTREAM_VVCT, VvcBRx_c, 5 ms, "packets after the restart");
                fetch_result(AXISTREAM_VVCT, VvcBRx_c, Cmd_v, Res_v, "truncated packet");
                -- Truncated packet: a prefix of packet 1 terminated by an EEP
                Ok_v := Res_v.data_length >= 2 and Res_v.data_length <= 201;
                if Ok_v then

                    for i in 0 to Res_v.data_length - 2 loop
                        if to_integer(unsigned(Res_v.data_array(i))) /= (1 + i) mod 256 then
                            Ok_v := false;
                        end if;
                    end loop;

                    Ok_v := Ok_v and Res_v.data_array(Res_v.data_length - 1) = x"01";
                end if;
                check_value(Ok_v, error, "packet 1: prefix of " & to_string(Res_v.data_length - 1) &
                            " bytes terminated by an EEP");
                check_value(StatA.CntRun, 2, error, "A restarted once");
                check_value(StatB.CntRun, 2, error, "B restarted once");
                check_value(StatA.Cause, CauseDisconnect_c, error, "cause at A");

            elsif run("test_ecc_tx") then
                -- TC-DL-50
                LinkMode        <= '1';
                CtrlA.LinkStart <= '1';
                CtrlB.LinkStart <= '1';
                waitState(0, StateRun_c, 60 us, "A");
                waitState(1, StateRun_c, 60 us, "B");
                -- Single error in the transmit FIFO: corrected
                wait until rising_edge(UserClk);
                CtrlA.InjTxFlip  <= (3 => '1', others => '0');
                CtrlA.InjTxValid <= '1';
                wait until rising_edge(UserClk);
                CtrlA.InjTxValid <= '0';
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(20, 1), "packet with SEC");
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(20, 1), "packet with SEC");
                await_completion(AXISTREAM_VVCT, VvcBRx_c, 1 ms, "packet received");
                check_value(StatA.CntTxSec, 1, error, "SEC counted");
                -- Double error: the corrupted N-Char becomes an EEP, the rest of the packet is discarded
                wait until rising_edge(UserClk);
                CtrlA.InjTxFlip  <= (3 => '1', 5 => '1', others => '0');
                CtrlA.InjTxValid <= '1';
                wait until rising_edge(UserClk);
                CtrlA.InjTxValid <= '0';
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(20, 2), "packet with DED");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(20, 3), "next packet");
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(0, 0, true), "EEP");
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(20, 3), "next packet");
                await_completion(AXISTREAM_VVCT, VvcBRx_c, 1 ms, "packets received");
                check_value(StatA.CntTxDed, 1, error, "DED counted");
                check_value(StatA.CntRun, 1, error, "no link restart");

            elsif run("test_ecc_rx") then
                -- TC-DL-51
                LinkMode        <= '1';
                CtrlA.LinkStart <= '1';
                CtrlB.LinkStart <= '1';
                waitState(0, StateRun_c, 60 us, "A");
                waitState(1, StateRun_c, 60 us, "B");
                -- Single error in the receive FIFO of A
                wait until rising_edge(LinkClk);
                CtrlA.InjRxFlip  <= (6 => '1', others => '0');
                CtrlA.InjRxValid <= '1';
                wait until rising_edge(LinkClk);
                CtrlA.InjRxValid <= '0';
                axistream_transmit(AXISTREAM_VVCT, VvcBTx_c, owrCountPacket(20, 4), "packet with SEC");
                axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(20, 4), "packet with SEC");
                await_completion(AXISTREAM_VVCT, VvcARx_c, 1 ms, "packet received");
                check_value(StatA.CntRxSec, 1, error, "SEC counted");
                -- Double error
                wait until rising_edge(LinkClk);
                CtrlA.InjRxFlip  <= (6 => '1', 9 => '1', others => '0');
                CtrlA.InjRxValid <= '1';
                wait until rising_edge(LinkClk);
                CtrlA.InjRxValid <= '0';
                axistream_transmit(AXISTREAM_VVCT, VvcBTx_c, owrCountPacket(20, 5), "packet with DED");
                axistream_transmit(AXISTREAM_VVCT, VvcBTx_c, owrCountPacket(20, 6), "next packet");
                axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(0, 0, true), "EEP");
                axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(20, 6), "next packet");
                await_completion(AXISTREAM_VVCT, VvcARx_c, 1 ms, "packets received");
                check_value(StatA.CntRxDed, 1, error, "DED counted");
            end if;

            -- Common end checks
            check_value(StatA.CntOverflow + StatB.CntOverflow, 0, error, "no receive overflow");
        end loop;

        owrTestEnd(runner);
    end process;

    i_th : entity work.owr_dl_th
        port map (
            LinkClk  => LinkClk,
            UserClk  => UserClk,
            Rst      => Rst,
            CtrlA    => CtrlA,
            CtrlB    => CtrlB,
            StatA    => StatA,
            StatB    => StatB,
            LinkMode => LinkMode,
            Cut      => Cut
        );

end architecture;
