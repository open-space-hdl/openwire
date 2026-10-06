---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the Network layer: time-code service, distributed interrupt service in both modes,
-- broadcast code priority and decoding, disabled services, FIFOs with error injection.
--
-- Documentation: hdl/owr_ni/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.owr_pkg.all;
    use work.owr_tb_pkg.all;
    use work.owr_tb_ds_pkg.all;
    use work.owr_tb_farend_pkg.all;
    use work.owr_ni_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_ni_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_ni_tb is

    constant KindTc_c  : natural := 0;
    constant KindInt_c : natural := 1;
    constant KindAck_c : natural := 2;

    signal LinkClk : std_logic;
    signal UserClk : std_logic;
    signal Rst     : std_logic := '1';
    signal NiIn1   : NiIn_t    := NiInInit_c;
    signal NiOut1  : NiOut_t;
    signal NiIn2   : NiIn_t    := NiInInit_c;
    signal NiOut2  : NiOut_t;

    -- Broadcast codes and indication log entries
    function tcCode (value : natural) return std_logic_vector is
    begin
        return "00" & std_logic_vector(to_unsigned(value, 6));
    end function;

    function intCode (iid : natural) return std_logic_vector is
    begin
        return "100" & std_logic_vector(to_unsigned(iid, 5));
    end function;

    function ackCode (iid : natural) return std_logic_vector is
    begin
        return "101" & std_logic_vector(to_unsigned(iid, 5));
    end function;

    function tcInd (value : natural) return std_logic_vector is
    begin
        return "00" & std_logic_vector(to_unsigned(value, 6));
    end function;

    function intInd (iid : natural) return std_logic_vector is
    begin
        return "010" & std_logic_vector(to_unsigned(iid, 5));
    end function;

    function ackInd (iid : natural) return std_logic_vector is
    begin
        return "100" & std_logic_vector(to_unsigned(iid, 5));
    end function;

begin

    test_runner_watchdog(runner, 10 ms);

    p_main : process is
        variable Cnt_v   : natural;
        variable T_v     : time;
        variable RxT_v   : time_vector(0 to 31);
        variable Found_v : boolean;

        -- Request on a user port of instance 1 (waits for the handshake)
        procedure userReq (
            kind  : natural;
            value : natural) is
        begin
            wait until rising_edge(UserClk);

            case kind is

                when KindTc_c =>
                    NiIn1.TcData  <= std_logic_vector(to_unsigned(value, 6));
                    NiIn1.TcValid <= '1';

                    loop
                        wait until rising_edge(UserClk);
                        exit when NiOut1.TcReady = '1';
                    end loop;

                    NiIn1.TcValid <= '0';

                when KindInt_c =>
                    NiIn1.IntData  <= std_logic_vector(to_unsigned(value, 5));
                    NiIn1.IntValid <= '1';

                    loop
                        wait until rising_edge(UserClk);
                        exit when NiOut1.IntReady = '1';
                    end loop;

                    NiIn1.IntValid <= '0';

                when others =>
                    NiIn1.AckData  <= std_logic_vector(to_unsigned(value, 5));
                    NiIn1.AckValid <= '1';

                    loop
                        wait until rising_edge(UserClk);
                        exit when NiOut1.AckReady = '1';
                    end loop;

                    NiIn1.AckValid <= '0';

            end case;

        end procedure;

        -- Request of the MIB of instance 1 (one cycle)
        procedure mibReq (
            kind  : natural;
            value : natural) is
        begin
            wait until rising_edge(LinkClk);

            case kind is

                when KindTc_c =>
                    NiIn1.MibTcValue <= std_logic_vector(to_unsigned(value, 6));
                    NiIn1.MibTcValid <= '1';

                when KindInt_c =>
                    NiIn1.MibIntIid   <= std_logic_vector(to_unsigned(value, 5));
                    NiIn1.MibIntValid <= '1';

                when others =>
                    NiIn1.MibAckIid   <= std_logic_vector(to_unsigned(value, 5));
                    NiIn1.MibAckValid <= '1';

            end case;

            wait until rising_edge(LinkClk);
            NiIn1.MibTcValid  <= '0';
            NiIn1.MibIntValid <= '0';
            NiIn1.MibAckValid <= '0';
        end procedure;

        -- Received broadcast code at instance 1 or 2
        procedure rxCode (
            inst : natural;
            code : std_logic_vector(7 downto 0)) is
        begin
            wait until rising_edge(LinkClk);
            if inst = 1 then
                NiIn1.RxData  <= code;
                NiIn1.RxValid <= '1';
            else
                NiIn2.RxData  <= code;
                NiIn2.RxValid <= '1';
            end if;
            wait until rising_edge(LinkClk);
            NiIn1.RxValid <= '0';
            NiIn2.RxValid <= '0';
            wait for 200 ns;
        end procedure;

        -- Checks entry n of a log
        procedure checkLog (
            log  : natural;
            n    : natural;
            data : std_logic_vector(7 downto 0);
            msg  : string) is
        begin
            if FarEnd_v.rxCount(log) > n then
                check_value(FarEnd_v.rxGet(log, n).Data, data, error, msg);
            else
                alert(ERROR, msg & ": entry " & to_string(n) & " missing (" & to_string(FarEnd_v.rxCount(log)) &
                      " entries)");
            end if;
        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);

        while test_suite loop

            Rst <= '1';
            wait for 100 ns;
            wait until rising_edge(LinkClk);
            Rst <= '0';
            wait for 100 ns;

            if run("test_tc_send") then
                -- TC-NI-01
                userReq(KindTc_c, 5);
                wait for 500 ns;
                checkLog(LogTx1_c, 0, tcCode(5), "time-code of the user port");
                check_value(NiOut1.TimeCode, "000101", error, "register loaded with the value sent");
                mibReq(KindTc_c, 9);
                wait for 200 ns;
                checkLog(LogTx1_c, 1, tcCode(9), "time-code of the MIB");
                -- A request replaces a waiting one
                NiIn1.DlReady <= '0';
                userReq(KindTc_c, 20);
                userReq(KindTc_c, 21);
                wait for 500 ns;
                NiIn1.DlReady <= '1';
                wait for 200 ns;
                check_value(FarEnd_v.rxCount(LogTx1_c), 3, error, "one time-code for two requests");
                checkLog(LogTx1_c, 2, tcCode(21), "latest value sent");
                check_value(NiOut1.TimeCode, "010101", error, "register");

            elsif run("test_tc_receive") then
                -- TC-NI-02
                mibReq(KindTc_c, 5);
                wait for 200 ns;
                rxCode(1, tcCode(6));
                rxCode(1, tcCode(8));
                rxCode(1, tcCode(9));
                wait for 500 ns;
                check_value(NiOut1.CntTcValid, 2, error, "valid time-codes");
                check_value(NiOut1.CntTcInv, 1, error, "invalid time-code");
                check_value(FarEnd_v.rxCount(LogInd1_c), 2, error, "indications");
                checkLog(LogInd1_c, 0, tcInd(6), "indication of 6");
                checkLog(LogInd1_c, 1, tcInd(9), "indication of 9");
                check_value(NiOut1.TimeCode, "001001", error, "register after 9");
                -- Wrap-around modulo 64
                mibReq(KindTc_c, 63);
                wait for 200 ns;
                rxCode(1, tcCode(0));
                wait for 500 ns;
                checkLog(LogInd1_c, 2, tcInd(0), "0 after 63 is valid");

            elsif run("test_tc_port_reset") then
                -- TC-NI-03
                mibReq(KindTc_c, 33);
                wait for 200 ns;
                check_value(NiOut1.TimeCode, "100001", error, "register 33");
                wait until rising_edge(LinkClk);
                NiIn1.PortReset <= '1';
                wait until rising_edge(LinkClk);
                NiIn1.PortReset <= '0';
                wait for 100 ns;
                check_value(NiOut1.TimeCode, "000000", error, "register zero after port reset");
                rxCode(1, tcCode(1));
                wait for 500 ns;
                check_value(NiOut1.CntTcValid, 1, error, "1 after port reset is valid");

            elsif run("test_bc_priority") then
                -- TC-NI-04
                NiIn1.AckMode <= '1';
                rxCode(1, intCode(4));
                NiIn1.DlReady <= '0';
                mibReq(KindInt_c, 10);
                mibReq(KindAck_c, 4);
                mibReq(KindTc_c, 7);
                wait for 200 ns;
                NiIn1.DlReady <= '1';
                wait for 200 ns;
                checkLog(LogTx1_c, 0, tcCode(7), "time-code first");
                checkLog(LogTx1_c, 1, ackCode(4), "acknowledgement second");
                checkLog(LogTx1_c, 2, intCode(10), "interrupt last");
                -- Simultaneous requests on the user ports, each valid until its handshake
                rxCode(1, intCode(6));
                NiIn1.DlReady  <= '0';
                wait until rising_edge(UserClk);
                NiIn1.TcData   <= "001100";
                NiIn1.TcValid  <= '1';
                NiIn1.IntData  <= "00011";
                NiIn1.IntValid <= '1';
                NiIn1.AckData  <= "00110";
                NiIn1.AckValid <= '1';

                for i in 0 to 9 loop
                    wait until rising_edge(UserClk);
                    if NiOut1.TcReady = '1' then
                        NiIn1.TcValid <= '0';
                    end if;
                    if NiOut1.IntReady = '1' then
                        NiIn1.IntValid <= '0';
                    end if;
                    if NiOut1.AckReady = '1' then
                        NiIn1.AckValid <= '0';
                    end if;
                end loop;

                wait for 300 ns;
                NiIn1.DlReady <= '1';
                wait for 200 ns;
                check_value(FarEnd_v.rxCount(LogTx1_c), 6, error, "codes sent");
                checkLog(LogTx1_c, 3, tcCode(12), "time-code first");
                checkLog(LogTx1_c, 4, ackCode(6), "acknowledgement second");
                checkLog(LogTx1_c, 5, intCode(3), "interrupt last");

            elsif run("test_bc_types") then
                -- TC-NI-05
                NiIn1.AckMode <= '1';
                rxCode(1, x"40");
                rxCode(1, x"C0");
                rxCode(1, x"7F");
                rxCode(1, x"FF");
                check_value(NiOut1.CntIgnored, 4, error, "types 0b01 and 0b11 discarded");
                check_value(FarEnd_v.rxCount(LogInd1_c), 0, error, "no indication");
                rxCode(1, tcCode(1));
                rxCode(1, intCode(17));
                rxCode(1, ackCode(18));
                wait for 300 ns;
                checkLog(LogInd1_c, 0, tcInd(1), "time-code");
                checkLog(LogInd1_c, 1, intInd(17), "interrupt code");
                checkLog(LogInd1_c, 2, ackInd(18), "acknowledgement code");
                check_value(NiOut1.CntIgnored, 4, error, "no further discard");

            elsif run("test_int_send") then
                -- TC-NI-06
                NiIn1.IntTick    <= x"000A";
                NiIn1.IntHoldoff <= x"0005";
                userReq(KindInt_c, 3);
                wait for 200 ns;
                checkLog(LogTx1_c, 0, intCode(3), "interrupt code 3");
                -- Within the minimum interval: discarded
                mibReq(KindInt_c, 3);
                wait for 50 ns;
                check_value(NiOut1.CntIntDisc, 1, error, "request within the minimum interval discarded");
                wait for 1 us;
                mibReq(KindInt_c, 3);
                wait for 200 ns;
                checkLog(LogTx1_c, 1, intCode(3), "interrupt code 3 after the interval");
                -- While waiting: discarded; several waiting codes: highest identifier first
                NiIn1.DlReady <= '0';
                mibReq(KindInt_c, 8);
                mibReq(KindInt_c, 8);
                mibReq(KindInt_c, 30);
                mibReq(KindInt_c, 1);
                wait for 100 ns;
                check_value(NiOut1.CntIntDisc, 2, error, "request of a waiting identifier discarded");
                NiIn1.DlReady <= '1';
                wait for 200 ns;
                checkLog(LogTx1_c, 2, intCode(30), "identifier 30 first");
                checkLog(LogTx1_c, 3, intCode(8), "identifier 8");
                checkLog(LogTx1_c, 4, intCode(1), "identifier 1");
                -- A code discarded outside Run does not start the interval
                NiIn1.DlDiscard <= '1';
                mibReq(KindInt_c, 12);
                wait for 100 ns;
                NiIn1.DlDiscard <= '0';
                mibReq(KindInt_c, 12);
                wait for 200 ns;
                checkLog(LogTx1_c, 5, intCode(12), "request after a discarded code accepted");
                check_value(NiOut1.CntIntDisc, 2, error, "no further discard");

            elsif run("test_int_receive") then
                -- TC-NI-07
                rxCode(1, intCode(7));
                rxCode(1, intCode(31));
                wait for 300 ns;
                check_value(NiOut1.IntActive, x"80000080", error, "interrupt register");
                checkLog(LogInd1_c, 0, intInd(7), "indication 7");
                checkLog(LogInd1_c, 1, intInd(31), "indication 31");
                check_value(NiOut1.CntIntRx, 2, error, "interrupts received");

            elsif run("test_int_modes") then
                -- TC-NI-08
                -- Interrupt with acknowledgement mode: acknowledgement code after the minimum delay
                NiIn1.AckMode  <= '1';
                NiIn1.IntTick  <= x"0064";
                NiIn1.AckDelay <= x"0003";
                rxCode(1, intCode(4));
                userReq(KindAck_c, 4);
                T_v            := now;
                wait for 100 ns;
                check_value(NiOut1.IntActive(4), '0', error, "interrupt cleared by the acknowledgement request");
                check_value(FarEnd_v.rxCount(LogTx1_c), 0, error, "acknowledgement held");

                while FarEnd_v.rxCount(LogTx1_c) = 0 and now < T_v + 10 us loop
                    wait until rising_edge(LinkClk);
                end loop;

                checkLog(LogTx1_c, 0, ackCode(4), "acknowledgement code");
                check_value(FarEnd_v.rxGet(LogTx1_c, 0).T - T_v >= 2.5 us, error,
                            "acknowledgement at least 3 ticks of 1 us after the interrupt code");
                -- Acknowledgement without a received interrupt: sent at once
                mibReq(KindAck_c, 9);
                wait for 100 ns;
                checkLog(LogTx1_c, 1, ackCode(9), "acknowledgement without interrupt");
                -- Received acknowledgement: indicated
                rxCode(1, ackCode(21));
                wait for 300 ns;
                checkLog(LogInd1_c, 1, ackInd(21), "acknowledgement indicated");
                check_value(NiOut1.LastAckIid, "10101", error, "identifier of the acknowledgement event");
                -- Interrupt mode: the request clears the bit and sends nothing, a received acknowledgement is
                -- discarded
                NiIn1.AckMode <= '0';
                rxCode(1, intCode(5));
                check_value(NiOut1.IntActive(5), '1', error, "interrupt 5 active");
                mibReq(KindAck_c, 5);
                wait for 1 us;
                check_value(NiOut1.IntActive(5), '0', error, "interrupt 5 cleared");
                check_value(FarEnd_v.rxCount(LogTx1_c), 2, error, "no acknowledgement code in interrupt mode");
                check_value(NiOut1.CntAckDisc, 1, error, "acknowledgement request discarded");
                rxCode(1, ackCode(5));
                check_value(NiOut1.CntIgnored, 1, error, "received acknowledgement discarded");
                check_value(NiOut1.CntAckRx, 1, error, "no further acknowledgement indication");

            elsif run("test_int_timers") then
                -- TC-NI-09
                NiIn1.IntTick    <= x"000A";
                NiIn1.IntHoldoff <= x"0005";
                mibReq(KindInt_c, 2);
                T_v              := now;
                -- Request every 100 ns until accepted: the interval is at least 5 ticks of 100 ns
                Cnt_v := 0;

                while FarEnd_v.rxCount(LogTx1_c) < 2 and now < T_v + 2 us loop
                    mibReq(KindInt_c, 2);
                    wait for 80 ns;
                end loop;

                check_value(FarEnd_v.rxCount(LogTx1_c), 2, error, "second interrupt code");
                T_v := FarEnd_v.rxGet(LogTx1_c, 1).T - FarEnd_v.rxGet(LogTx1_c, 0).T;
                check_value(T_v >= 500 ns and T_v <= 700 ns, error, "minimum interval " & to_string(T_v) &
                            " between 5 and 6 ticks plus latency");
                -- Tick every cycle (INT_TICK = 0): an interval of 5 cycles
                wait for 1 us;
                NiIn1.IntTick <= x"0000";
                Cnt_v         := FarEnd_v.rxCount(LogTx1_c);
                T_v           := now;

                while FarEnd_v.rxCount(LogTx1_c) < Cnt_v + 2 and now < T_v + 1 us loop
                    mibReq(KindInt_c, 3);
                end loop;

                check_value(FarEnd_v.rxCount(LogTx1_c), Cnt_v + 2, error, "two interrupt codes with a tick per cycle");
                T_v := FarEnd_v.rxGet(LogTx1_c, Cnt_v + 1).T - FarEnd_v.rxGet(LogTx1_c, Cnt_v).T;
                check_value(T_v >= 50 ns and T_v <= 120 ns, error, "minimum interval " & to_string(T_v) &
                            " between 5 and 6 cycles plus latency");
                -- Acknowledgement delay of every identifier: 100 ticks of 100 ns after its interrupt code
                NiIn1.AckMode  <= '1';
                NiIn1.IntTick  <= x"000A";
                NiIn1.AckDelay <= x"0064";
                Cnt_v          := FarEnd_v.rxCount(LogTx1_c);

                for i in 0 to 31 loop
                    rxCode(1, intCode(i));
                    -- Clock edge at which the code was received
                    RxT_v(i) := now - 200 ns;
                end loop;

                for i in 0 to 31 loop
                    mibReq(KindAck_c, i);
                end loop;

                check_value(FarEnd_v.rxCount(LogTx1_c), Cnt_v, error, "acknowledgements held");
                T_v := now;

                while FarEnd_v.rxCount(LogTx1_c) < Cnt_v + 32 and now < T_v + 20 us loop
                    wait until rising_edge(LinkClk);
                end loop;

                check_value(FarEnd_v.rxCount(LogTx1_c), Cnt_v + 32, error, "32 acknowledgement codes");

                for i in 0 to 31 loop
                    Found_v := false;

                    for n in Cnt_v to FarEnd_v.rxCount(LogTx1_c) - 1 loop
                        if FarEnd_v.rxGet(LogTx1_c, n).Data = ackCode(i) then
                            Found_v := true;
                            check_value(FarEnd_v.rxGet(LogTx1_c, n).T - RxT_v(i) >= 10 us, error,
                                        "acknowledgement " & to_string(i) & " at least 100 ticks after the interrupt");
                        end if;
                    end loop;

                    check_value(Found_v, error, "acknowledgement code " & to_string(i));
                end loop;

            elsif run("test_int_port_reset") then
                -- TC-NI-10
                NiIn1.AckMode    <= '1';
                NiIn1.IntTick    <= x"0064";
                NiIn1.IntHoldoff <= x"00FF";
                NiIn1.AckDelay   <= x"00FF";
                rxCode(1, intCode(1));
                mibReq(KindInt_c, 2);
                mibReq(KindAck_c, 1);
                NiIn1.DlReady    <= '0';
                mibReq(KindInt_c, 3);
                wait until rising_edge(LinkClk);
                NiIn1.PortReset  <= '1';
                wait until rising_edge(LinkClk);
                NiIn1.PortReset  <= '0';
                NiIn1.DlReady    <= '1';
                wait for 500 ns;
                check_value(NiOut1.IntActive, x"00000000", error, "interrupt register cleared");
                -- Only the code sent before the reset; the waiting ones are gone, the timers stopped
                check_value(FarEnd_v.rxCount(LogTx1_c), 1, error, "waiting codes cleared");
                mibReq(KindInt_c, 2);
                wait for 200 ns;
                checkLog(LogTx1_c, 1, intCode(2), "interval cleared by port reset");

            elsif run("test_disabled_services") then
                -- TC-NI-11
                rxCode(2, tcCode(1));
                rxCode(2, intCode(1));
                rxCode(2, ackCode(1));
                wait for 300 ns;
                check_value(NiOut2.CntIgnored, 3, error, "codes of disabled services ignored");
                check_value(FarEnd_v.rxCount(LogInd2_c), 0, error, "no indication");
                wait until rising_edge(LinkClk);
                NiIn2.MibTcValid  <= '1';
                NiIn2.MibIntValid <= '1';
                wait until rising_edge(LinkClk);
                NiIn2.MibTcValid  <= '0';
                NiIn2.MibIntValid <= '0';
                wait for 300 ns;
                check_value(FarEnd_v.rxCount(LogTx2_c), 0, error, "requests of disabled services discarded");
                check_value(NiOut2.CntIntDisc, 1, error, "interrupt request reported");

            elsif run("test_ind_overflow") then
                -- TC-NI-12
                NiIn1.IndReady <= '0';

                for i in 0 to 19 loop
                    rxCode(1, intCode(i));
                end loop;

                check_value(NiOut1.CntIndOvf > 0, error, "indications lost when the FIFO is full");
                Cnt_v          := NiOut1.CntIndOvf;
                NiIn1.IndReady <= '1';
                wait for 1 us;
                check_value(FarEnd_v.rxCount(LogInd1_c), 20 - Cnt_v, error, "indications in the FIFO delivered");
                checkLog(LogInd1_c, 0, intInd(0), "first indication");

            elsif run("test_ecc") then
                -- TC-NI-13
                -- Single error in the request FIFO: corrected
                wait until rising_edge(UserClk);
                NiIn1.InjReqFlip  <= (2 => '1', others => '0');
                NiIn1.InjReqValid <= '1';
                wait until rising_edge(UserClk);
                NiIn1.InjReqValid <= '0';
                userReq(KindTc_c, 17);
                wait for 300 ns;
                checkLog(LogTx1_c, 0, tcCode(17), "corrected request");
                check_value(NiOut1.CntReqSec, 1, error, "SEC of the request FIFO");
                -- Double error: discarded
                wait until rising_edge(UserClk);
                NiIn1.InjReqFlip  <= (2 => '1', 4 => '1', others => '0');
                NiIn1.InjReqValid <= '1';
                wait until rising_edge(UserClk);
                NiIn1.InjReqValid <= '0';
                userReq(KindTc_c, 18);
                wait for 300 ns;
                check_value(FarEnd_v.rxCount(LogTx1_c), 1, error, "request with double error discarded");
                check_value(NiOut1.CntReqDed, 1, error, "DED of the request FIFO");
                -- Indication FIFO
                wait until rising_edge(LinkClk);
                NiIn1.InjIndFlip  <= (3 => '1', others => '0');
                NiIn1.InjIndValid <= '1';
                wait until rising_edge(LinkClk);
                NiIn1.InjIndValid <= '0';
                rxCode(1, intCode(9));
                wait until rising_edge(LinkClk);
                NiIn1.InjIndFlip  <= (3 => '1', 6 => '1', others => '0');
                NiIn1.InjIndValid <= '1';
                wait until rising_edge(LinkClk);
                NiIn1.InjIndValid <= '0';
                rxCode(1, intCode(10));
                wait for 500 ns;
                check_value(FarEnd_v.rxCount(LogInd1_c), 1, error, "indication with double error discarded");
                checkLog(LogInd1_c, 0, intInd(9), "corrected indication");
                check_value(NiOut1.CntIndSec, 1, error, "SEC of the indication FIFO");
                check_value(NiOut1.CntIndDed, 1, error, "DED of the indication FIFO");
            end if;

        end loop;

        owrTestEnd(runner);
    end process;

    i_th : entity work.owr_ni_th
        port map (
            LinkClk => LinkClk,
            UserClk => UserClk,
            Rst     => Rst,
            NiIn1   => NiIn1,
            NiOut1  => NiOut1,
            NiIn2   => NiIn2,
            NiOut2  => NiOut2
        );

end architecture;
