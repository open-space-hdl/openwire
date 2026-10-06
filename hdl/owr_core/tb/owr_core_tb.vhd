---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the OpenWire core: two cores with different clocks on a line, and one core against
-- the Data-Strobe far-end model. Operational sequences through the MIB, packets, time-codes,
-- distributed interrupts, line errors, port reset, loopback, data signalling rates, EDAC.
--
-- Documentation: hdl/owr_core/docs/verification_plan.md

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

library bitvis_vip_axilite;
    context bitvis_vip_axilite.vvc_context;

library bitvis_vip_axistream;
    context bitvis_vip_axistream.vvc_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.owr_pkg.all;
    use work.owr_regs_pkg.all;
    use work.owr_tb_pkg.all;
    use work.owr_tb_ds_pkg.all;
    use work.owr_tb_farend_pkg.all;
    use work.owr_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_core_tb is
    generic (
        runner_cfg  : string;
        ServicesB_g : boolean := true
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_core_tb is

    constant A_c : natural := 0;
    constant B_c : natural := 1;

    signal Rst      : std_logic  := '1';
    signal BcInA    : CoreBcIn_t := CoreBcInInit_c;
    signal BcInB    : CoreBcIn_t := CoreBcInInit_c;
    signal ObsA     : CoreObs_t;
    signal ObsB     : CoreObs_t;
    signal UserClkA : std_logic;
    signal UserClkB : std_logic;
    signal LinkClkA : std_logic;
    signal LinkMode : std_logic  := '0';
    signal Cut      : std_logic  := '0';
    signal Glitch   : std_logic  := '0';

begin

    test_runner_watchdog(runner, 100 ms);

    p_main : process is
        variable Data_v  : std_logic_vector(31 downto 0);
        variable T_v     : time;
        variable T2_v    : time;
        variable Cnt_v   : natural;
        variable Cmd_v   : natural;
        variable Res_v   : bitvis_vip_axistream.vvc_cmd_pkg.t_vvc_result;
        variable Ok_v    : boolean;
        variable Start_v : natural;

        procedure regWrite (
            core : natural;
            addr : natural;
            data : std_logic_vector(31 downto 0)) is
        begin
            axilite_write(AXILITE_VVCT, core, to_unsigned(addr, 8), data, "write 0x" & to_hstring(to_unsigned(addr, 8)));
            await_completion(AXILITE_VVCT, core, 100 us);
        end procedure;

        procedure regRead (
            core :     natural;
            addr :     natural;
            data : out std_logic_vector(31 downto 0)) is
            variable Cmd_v    : natural;
            variable Result_v : bitvis_vip_axilite.vvc_cmd_pkg.t_vvc_result;
        begin
            axilite_read(AXILITE_VVCT, core, to_unsigned(addr, 8), "read");
            Cmd_v := get_last_received_cmd_idx(AXILITE_VVCT, core);
            await_completion(AXILITE_VVCT, core, 100 us);
            fetch_result(AXILITE_VVCT, core, Cmd_v, Result_v, "fetch");
            data  := Result_v(31 downto 0);
        end procedure;

        procedure regCheck (
            core : natural;
            addr : natural;
            data : std_logic_vector(31 downto 0);
            msg  : string) is
        begin
            axilite_check(AXILITE_VVCT, core, to_unsigned(addr, 8), data, msg);
            await_completion(AXILITE_VVCT, core, 100 us);
        end procedure;

        procedure regCheckMask (
            core : natural;
            addr : natural;
            mask : std_logic_vector(31 downto 0);
            data : std_logic_vector(31 downto 0);
            msg  : string) is
            variable Data_v : std_logic_vector(31 downto 0);
        begin
            regRead(core, addr, Data_v);
            check_value(Data_v and mask, data, error, msg);
        end procedure;

        -- Polls PORT_STATUS until the link state is reached
        procedure waitState (
            core    : natural;
            state   : LinkState_t;
            timeout : time;
            msg     : string) is
            variable End_v  : time;
            variable Data_v : std_logic_vector(31 downto 0);
        begin
            End_v := now + timeout;

            loop
                regRead(core, RegPortStatus_c, Data_v);
                exit when Data_v(2 downto 0) = state or now > End_v;
                wait for 1 us;
            end loop;

            check_value(Data_v(2 downto 0), state, error, msg & ": link state");
        end procedure;

        -- Software start of the link: link speeds, A with LinkStart, B with AutoStart
        procedure startLink (
            divA : natural;
            divB : natural) is
        begin
            regWrite(A_c, RegLinkSpeed_c, std_logic_vector(to_unsigned(divA, 32)));
            regWrite(B_c, RegLinkSpeed_c, std_logic_vector(to_unsigned(divB, 32)));
            regWrite(B_c, RegPortCtrl_c, x"00000038");
            regWrite(A_c, RegPortCtrl_c, x"00000034");
            waitState(A_c, StateRun_c, 200 us, "core A");
            waitState(B_c, StateRun_c, 50 us, "core B");
        end procedure;

        -- Request on a broadcast service port: kind 0 time-code, 1 interrupt, 2 acknowledgement
        procedure bcReq (
            core  : natural;
            kind  : natural;
            value : natural) is
        begin
            if core = A_c then
                wait until rising_edge(UserClkA);

                case kind is

                    when 0 =>
                        BcInA.TcData  <= std_logic_vector(to_unsigned(value, 6));
                        BcInA.TcValid <= '1';

                    when 1 =>
                        BcInA.IntData  <= std_logic_vector(to_unsigned(value, 5));
                        BcInA.IntValid <= '1';

                    when others =>
                        BcInA.AckData  <= std_logic_vector(to_unsigned(value, 5));
                        BcInA.AckValid <= '1';

                end case;

                loop
                    wait until rising_edge(UserClkA);
                    exit when (kind = 0 and ObsA.TcReady = '1') or (kind = 1 and ObsA.IntReady = '1') or
                              (kind = 2 and ObsA.AckReady = '1');
                end loop;

                BcInA.TcValid  <= '0';
                BcInA.IntValid <= '0';
                BcInA.AckValid <= '0';
            else
                wait until rising_edge(UserClkB);

                case kind is

                    when 0 =>
                        BcInB.TcData  <= std_logic_vector(to_unsigned(value, 6));
                        BcInB.TcValid <= '1';

                    when 1 =>
                        BcInB.IntData  <= std_logic_vector(to_unsigned(value, 5));
                        BcInB.IntValid <= '1';

                    when others =>
                        BcInB.AckData  <= std_logic_vector(to_unsigned(value, 5));
                        BcInB.AckValid <= '1';

                end case;

                loop
                    wait until rising_edge(UserClkB);
                    exit when (kind = 0 and ObsB.TcReady = '1') or (kind = 1 and ObsB.IntReady = '1') or
                              (kind = 2 and ObsB.AckReady = '1');
                end loop;

                BcInB.TcValid  <= '0';
                BcInB.IntValid <= '0';
                BcInB.AckValid <= '0';
            end if;
        end procedure;

        -- Entry n of an indication log
        procedure checkInd (
            log  : natural;
            n    : natural;
            data : std_logic_vector(7 downto 0);
            msg  : string) is
        begin
            if FarEnd_v.rxCount(log) > n then
                check_value(FarEnd_v.rxGet(log, n).Data, data, error, msg);
            else
                alert(ERROR, msg & ": indication " & to_string(n) & " missing");
            end if;
        end procedure;

        procedure sendPackets (
            n     : natural;
            first : natural) is
        begin

            for i in 0 to n - 1 loop
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket((i * 61 + first) mod 300, i + first),
                                   "A to B");
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket((i * 61 + first) mod 300, i + first),
                                 "A to B");
            end loop;

        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);
        enable_log_msg(ID_SEQUENCER);
        disable_log_msg(AXILITE_VVCT, AxiA_c, ALL_MESSAGES);
        disable_log_msg(AXILITE_VVCT, AxiB_c, ALL_MESSAGES);

        for i in VvcATx_c to VvcBRx_c loop
            disable_log_msg(AXISTREAM_VVCT, i, ALL_MESSAGES);
        end loop;

        while test_suite loop

            Rst <= '1';
            wait for 200 ns;
            Rst <= '0';
            wait for 500 ns;

            if run("test_link_startup") then
                -- TC-CORE-01
                regCheck(A_c, RegId_c, RegMapId_c, "ID of A");
                regCheck(B_c, RegId_c, RegMapId_c, "ID of B");
                regCheck(B_c, RegClkFreq_c, std_logic_vector(to_unsigned(125000, 32)), "clock of B");
                regCheck(B_c, RegLinkSpeed_c, x"00000D01", "initial divider of B: 13 (9.6 Mb/s)");
                -- Without software both ports stay in Ready
                wait for 30 us;
                regCheck(A_c, RegPortStatus_c, x"00000002", "A in Ready");
                regWrite(A_c, RegEventsIrqEn_c, x"00000001");
                regWrite(B_c, RegEventsIrqEn_c, x"00000001");
                startLink(2, 3);
                wait for 10 us;
                check_value(ObsA.Irq, '1', error, "interrupt of A on link up");
                check_value(ObsB.Irq, '1', error, "interrupt of B on link up");
                regCheck(A_c, RegEvents_c, x"00000001", "EVENTS of A: link up");
                regCheck(A_c, RegLinkCounts_c, x"00000001", "one Run entry");
                regCheck(A_c, RegCredit_c, x"00003838", "credits of A: 56 and 56");
                regCheck(B_c, RegCredit_c, x"00003838", "credits of B: 56 and 56");
                regCheck(A_c, RegErrors_c, x"00000000", "no error at A");
                check_value(ObsA.PhyTxEn and ObsA.PhyRxEn, '1', error, "line driver and receiver enabled");

            elsif run("test_packets") then
                -- TC-CORE-02
                startLink(2, 3);

                for i in 0 to 39 loop
                    axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket((i * 97) mod 501, i, i mod 9 = 4),
                                       "A to B " & to_string(i));
                    axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket((i * 97) mod 501, i, i mod 9 = 4),
                                     "A to B " & to_string(i));
                    axistream_transmit(AXISTREAM_VVCT, VvcBTx_c, owrCountPacket((i * 71) mod 401, i + 100, false),
                                       "B to A " & to_string(i));
                    axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket((i * 71) mod 401, i + 100, false),
                                     "B to A " & to_string(i));
                end loop;

                await_completion(AXISTREAM_VVCT, VvcBRx_c, 50 ms, "A to B");
                await_completion(AXISTREAM_VVCT, VvcARx_c, 50 ms, "B to A");
                regCheck(A_c, RegErrors_c, x"00000000", "no error at A");
                regCheck(B_c, RegErrors_c, x"00000000", "no error at B");
                regCheck(A_c, RegLinkCounts_c, x"00000001", "no restart");

            elsif run("test_time_codes") then
                -- TC-CORE-03
                startLink(2, 2);

                for i in 1 to 70 loop
                    bcReq(A_c, 0, i mod 64);
                    wait for 1 us;
                end loop;

                wait for 2 us;
                check_value(FarEnd_v.rxCount(IndB_c), 70, error, "70 valid time-codes indicated at B");
                Ok_v := true;

                for i in 1 to minimum(70, FarEnd_v.rxCount(IndB_c)) loop
                    if FarEnd_v.rxGet(IndB_c, i - 1).Data /= "00" & std_logic_vector(to_unsigned(i mod 64, 6)) then
                        Ok_v := false;
                    end if;
                end loop;

                check_value(Ok_v, error, "time-code values in order");
                regCheck(A_c, RegTimeCode_c, x"00000006", "time-code register of A (70 mod 64)");
                regCheck(B_c, RegTimeCode_c, x"00000006", "time-code register of B");
                -- A time-code that is not the next one: invalid at B, register updated, no indication
                regWrite(A_c, RegTcSend_c, x"0000000A");
                wait for 2 us;
                regCheck(B_c, RegTimeCode_c, x"0000000A", "register of B after an invalid time-code");
                regCheck(B_c, RegTcCounts_c, x"00010046", "B: 70 valid, 1 invalid");
                check_value(FarEnd_v.rxCount(IndB_c), 70, error, "no indication of the invalid time-code");
                regCheck(A_c, RegErrors_c, x"00000000", "no error at A");

            elsif run("test_interrupts") then
                -- TC-CORE-04
                regWrite(A_c, RegIntCtrl_c, x"00000001");
                regWrite(B_c, RegIntCtrl_c, x"00000001");
                startLink(2, 2);
                -- Interrupt with acknowledgement: A interrupts, B acknowledges
                bcReq(A_c, 1, 5);
                wait for 2 us;
                checkInd(IndB_c, 0, "01000101", "interrupt 5 indicated at B");
                regCheck(B_c, RegIntActive_c, x"00000020", "interrupt register of B");
                bcReq(B_c, 2, 5);
                wait for 2 us;
                regCheck(B_c, RegIntActive_c, x"00000000", "interrupt register of B cleared");
                checkInd(IndA_c, 0, "10000101", "acknowledgement 5 indicated at A");
                regCheck(A_c, RegAckReceived_c, x"00000020", "ACK_RECEIVED of A");
                -- Interrupts of the MIB, several identifiers
                regWrite(A_c, RegIntSend_c, x"0000001F");
                regWrite(A_c, RegIntSend_c, x"00000000");
                wait for 2 us;
                regCheck(B_c, RegIntActive_c, x"80000001", "interrupts 0 and 31 at B");
                -- Interrupt mode: the acknowledgement request clears the register and sends nothing
                regWrite(A_c, RegIntCtrl_c, x"00000000");
                regWrite(B_c, RegIntCtrl_c, x"00000000");
                regWrite(B_c, RegIntAck_c, x"00000000");
                regWrite(B_c, RegIntAck_c, x"0000001F");
                wait for 2 us;
                regCheck(B_c, RegIntActive_c, x"00000000", "interrupt register of B cleared");
                check_value(FarEnd_v.rxCount(IndA_c), 1, error, "no acknowledgement in interrupt mode");
                regCheckMask(B_c, RegEvents_c, x"00000200", x"00000200", "B: acknowledgement request discarded");

            elsif run("test_line_errors") then
                -- TC-CORE-05
                startLink(1, 2);
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(400, 0), "packet 0");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(400, 1), "packet 1");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(100, 2), "packet 2");
                axistream_receive(AXISTREAM_VVCT, VvcBRx_c, "packet 0 (truncated)");
                Cmd_v := get_last_received_cmd_idx(AXISTREAM_VVCT, VvcBRx_c);
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(400, 1), "packet 1");
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(100, 2), "packet 2");
                -- Line cut in packet 0: both ports detect a disconnect and start again
                wait for 20 us;
                Cut <= '1';
                wait for 2 us;
                Cut <= '0';
                waitState(A_c, StateRun_c, 200 us, "A after the cut");
                waitState(B_c, StateRun_c, 50 us, "B after the cut");
                await_completion(AXISTREAM_VVCT, VvcBRx_c, 5 ms, "packets after the cut");
                fetch_result(AXISTREAM_VVCT, VvcBRx_c, Cmd_v, Res_v, "truncated packet");
                check_value(Res_v.data_length >= 2 and Res_v.data_array(Res_v.data_length - 1) = x"01", error,
                            "packet 0 truncated and terminated by an EEP");
                regCheck(A_c, RegPortStatus_c, x"00000215", "A: Run, gotNull, last cause disconnect");
                regCheck(A_c, RegErrors_c, x"00000001", "A: disconnect flag");
                regRead(A_c, RegLinkCounts_c, Data_v);
                check_value(Data_v, x"00010002", error, "A: two Run entries, one recovery");
                -- Glitch on the data line from A to B: a receive error at B, both ports start again
                regWrite(A_c, RegErrors_c, x"0000000F");
                regWrite(B_c, RegErrors_c, x"0000000F");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(300, 3), "packet 3");
                axistream_receive(AXISTREAM_VVCT, VvcBRx_c, "packet 3 (truncated)");
                Cmd_v  := get_last_received_cmd_idx(AXISTREAM_VVCT, VvcBRx_c);
                wait for 10 us;
                Glitch <= '1';
                wait for 10 ns;
                Glitch <= '0';
                wait for 5 us;
                waitState(B_c, StateRun_c, 200 us, "B after the glitch");
                await_completion(AXISTREAM_VVCT, VvcBRx_c, 5 ms, "packet 3");
                fetch_result(AXISTREAM_VVCT, VvcBRx_c, Cmd_v, Res_v, "truncated packet");
                check_value(Res_v.data_array(Res_v.data_length - 1) = x"01", error, "packet 3 terminated by an EEP");
                regRead(B_c, RegErrors_c, Data_v);
                check_value(Data_v(1) = '1' or Data_v(2) = '1', error, "B: parity or ESC error");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(50, 4), "packet 4");
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(50, 4), "packet 4");
                await_completion(AXISTREAM_VVCT, VvcBRx_c, 1 ms, "packet 4");

            elsif run("test_port_reset") then
                -- TC-CORE-06
                startLink(2, 2);
                regWrite(A_c, RegTcSend_c, x"00000005");
                wait for 2 us;
                regCheck(A_c, RegTimeCode_c, x"00000005", "time-code register 5");
                regWrite(A_c, RegPortCtrl_c, x"00000035");
                regCheck(A_c, RegTimeCode_c, x"00000000", "time-code register zero after port reset");
                waitState(A_c, StateRun_c, 200 us, "A after port reset");
                regCheckMask(A_c, RegLinkCounts_c, x"0000FFFF", x"00000002", "second Run entry");
                sendPackets(5, 7);
                await_completion(AXISTREAM_VVCT, VvcBRx_c, 5 ms, "packets after port reset");

            elsif run("test_loopback") then
                -- TC-CORE-07
                regWrite(A_c, RegLinkSpeed_c, x"00000003");
                regWrite(A_c, RegPortCtrl_c, x"00000074");
                waitState(A_c, StateRun_c, 200 us, "A with itself");

                for i in 0 to 9 loop
                    axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(i * 30, i), "looped " & to_string(i));
                    axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(i * 30, i), "looped " & to_string(i));
                end loop;

                await_completion(AXISTREAM_VVCT, VvcARx_c, 5 ms, "looped packets");
                regCheckMask(B_c, RegLinkCounts_c, x"0000FFFF", x"00000000", "B never in Run");

            elsif run("test_rates") then
                -- TC-CORE-08
                -- A sends at 100 Mb/s (divider 1 at 100 MHz), B at 13.9 Mb/s (divider 9 at 125 MHz)
                startLink(1, 9);
                sendPackets(20, 3);

                for i in 0 to 9 loop
                    axistream_transmit(AXISTREAM_VVCT, VvcBTx_c, owrCountPacket(i * 20 + 1, i), "B to A");
                    axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(i * 20 + 1, i), "B to A");
                end loop;

                await_completion(AXISTREAM_VVCT, VvcBRx_c, 20 ms, "A to B");
                await_completion(AXISTREAM_VVCT, VvcARx_c, 20 ms, "B to A");
                regCheck(A_c, RegLinkCounts_c, x"00000001", "no restart");

            elsif run("test_phy_enables") then
                -- TC-CORE-09
                check_value(ObsA.PhyTxEn and ObsA.PhyRxEn, '1', error, "enabled after reset");
                regWrite(A_c, RegPortCtrl_c, x"00000020");
                wait for 1 us;
                check_value(ObsA.PhyTxEn, '0', error, "line driver disabled");
                check_value(ObsA.PhyRxEn, '1', error, "line receiver enabled");
                regWrite(A_c, RegPortCtrl_c, x"00000010");
                wait for 1 us;
                check_value(ObsA.PhyTxEn, '1', error, "line driver enabled");
                check_value(ObsA.PhyRxEn, '0', error, "line receiver disabled");

            elsif run("test_ecc") then
                -- TC-CORE-10
                startLink(2, 2);
                -- Double error in the transmit FIFO of A: B receives an EEP, the rest of the packet is discarded
                regWrite(A_c, RegEccInject_c, x"00000200");
                wait for 2 us;
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(20, 1), "packet with DED");
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(20, 2), "next packet");
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(0, 0, true), "EEP");
                axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(20, 2), "next packet");
                await_completion(AXISTREAM_VVCT, VvcBRx_c, 1 ms, "packets");
                regCheck(A_c, RegEccCount_c, x"00010000", "A channel 0: one DED");
                regCheck(A_c, RegEccStatus_c, x"00000001", "A: DED flag of the transmit FIFO");
                regCheckMask(A_c, RegEvents_c, x"00002000", x"00002000", "A: ECC_DED event");
                -- Single error in the receive FIFO of B: corrected
                regWrite(B_c, RegEccInject_c, x"00000101");
                regWrite(B_c, RegEccSelect_c, x"00000001");
                wait for 2 us;
                sendPackets(1, 9);
                await_completion(AXISTREAM_VVCT, VvcBRx_c, 1 ms, "packet with SEC");
                wait for 1 us;
                regCheck(B_c, RegEccCount_c, x"00000001", "B channel 1: one SEC");

            elsif run("test_throughput") then
                -- TC-CORE-11
                -- A to B at 100 Mb/s while B sends to A at 62.5 Mb/s
                startLink(1, 2);
                T_v := now;

                for i in 0 to 19 loop
                    axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(1000, i), "A to B " & to_string(i));
                    axistream_expect(AXISTREAM_VVCT, VvcBRx_c, owrCountPacket(1000, i), "A to B " & to_string(i));
                    axistream_transmit(AXISTREAM_VVCT, VvcBTx_c, owrCountPacket(600, i), "B to A " & to_string(i));
                    axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(600, i), "B to A " & to_string(i));
                end loop;

                await_completion(AXISTREAM_VVCT, VvcBRx_c, 20 ms, "A to B");
                T2_v := now - T_v;
                await_completion(AXISTREAM_VVCT, VvcARx_c, 20 ms, "B to A");
                log(ID_SEQUENCER, "A to B: 20000 bytes in " & to_string(T2_v / 1 ns) & " ns, B to A: 12000 bytes in " &
                    to_string((now - T_v) / 1 ns) & " ns");
                -- 10 bits per data character: 2 ms at 100 Mb/s; 1.92 ms at 62.5 Mb/s
                check_value(T2_v < 2.2 ms, error, "A to B at 90 % or more of the data character rate");
                check_value(now - T_v < 2.15 ms, error, "B to A at 90 % or more of the data character rate");

            elsif run("test_link_disabled") then
                -- TC-CORE-12
                regWrite(B_c, RegLinkSpeed_c, x"00000002");
                regWrite(B_c, RegPortCtrl_c, x"00000038");
                regWrite(A_c, RegPortCtrl_c, x"00000036");
                wait for 50 us;
                regCheckMask(A_c, RegPortStatus_c, x"00000007", x"00000000", "A stays in ErrorReset");
                regCheckMask(B_c, RegPortStatus_c, x"00000007", x"00000002", "B waits in Ready");
                regWrite(A_c, RegPortCtrl_c, x"00000034");
                waitState(A_c, StateRun_c, 200 us, "A enabled");
                waitState(B_c, StateRun_c, 50 us, "B");
                -- LinkDisabled in Run: ErrorReset with the cause LinkDisabled
                regWrite(A_c, RegPortCtrl_c, x"00000036");
                wait for 2 us;
                regCheck(A_c, RegPortStatus_c, x"00000100", "A in ErrorReset, cause LinkDisabled");

            elsif run("test_far_end") then
                -- TC-CORE-13
                LinkMode <= '1';
                FarEnd_v.setBitPeriod(Far_c, 100 ns);
                FarEnd_v.setMode(Far_c, TbModeNull);
                FarEnd_v.setRxTimeout(Far_c, 5 us);
                regWrite(A_c, RegLinkSpeed_c, x"00000004");
                regWrite(A_c, RegPortCtrl_c, x"00000034");
                -- Initial rate 10 Mb/s until Run
                waitState(A_c, StateConnecting_c, 100 us, "A");
                wait for 4 us;
                Start_v := FarEnd_v.edgeCount(Far_c);
                wait for 2 us;
                check_value(FarEnd_v.edgeGet(Far_c, Start_v + 1).T - FarEnd_v.edgeGet(Far_c, Start_v).T, 100 ns, error,
                            "initial bit period before Run");
                check_value(tbRxCountKind(Far_c, TbFct), 7, error, "seven FCTs from A");
                FarEnd_v.txPush(Far_c, tbChar(TbFct));
                waitState(A_c, StateRun_c, 20 us, "A");
                wait for 2 us;
                Start_v := FarEnd_v.edgeCount(Far_c);
                wait for 1 us;
                check_value(FarEnd_v.edgeGet(Far_c, Start_v + 1).T - FarEnd_v.edgeGet(Far_c, Start_v).T, 40 ns, error,
                            "run bit period of 4 cycles in Run");

                -- A packet from the far end
                for i in 0 to 9 loop
                    FarEnd_v.txPush(Far_c, tbData(16#A0# + i));
                end loop;

                FarEnd_v.txPush(Far_c, tbChar(TbEop));
                axistream_expect(AXISTREAM_VVCT, VvcARx_c, owrCountPacket(10, 16#A0#), "packet of the far end");
                await_completion(AXISTREAM_VVCT, VvcARx_c, 1 ms, "packet of the far end");
                -- A packet to the far end (one FCT: 8 N-Chars)
                Start_v := FarEnd_v.rxCount(Far_c);
                axistream_transmit(AXISTREAM_VVCT, VvcATx_c, owrCountPacket(7, 16#30#), "packet to the far end");
                await_completion(AXISTREAM_VVCT, VvcATx_c, 1 ms, "packet to the far end");
                wait for 5 us;
                Cnt_v   := 0;

                for i in Start_v to FarEnd_v.rxCount(Far_c) - 1 loop
                    if FarEnd_v.rxGet(Far_c, i).Kind = TbData then
                        check_value(to_integer(unsigned(FarEnd_v.rxGet(Far_c, i).Data)), 16#30# + Cnt_v, error,
                                    "data character " & to_string(Cnt_v));
                        Cnt_v := Cnt_v + 1;
                    end if;
                end loop;

                check_value(Cnt_v, 7, error, "data characters at the far end");
                check_value(tbRxCountKind(Far_c, TbEop, Start_v), 1, error, "EOP at the far end");
                check_value(FarEnd_v.rxErrors(Far_c), 0, error, "no decoding error at the far end");
                -- Time-code from the far end
                FarEnd_v.txPush(Far_c, tbTimeCode(1));
                wait for 3 us;
                checkInd(IndA_c, 0, "00000001", "time-code of the far end indicated");

            elsif run("test_no_services") then
                -- TC-CORE-14 (configuration without the broadcast services at B)
                regCheck(B_c, RegGenerics_c, x"00001000", "B without time-codes and interrupts");
                startLink(2, 2);
                bcReq(A_c, 0, 1);
                bcReq(A_c, 1, 3);
                wait for 3 us;
                check_value(FarEnd_v.rxCount(IndB_c), 0, error, "no indication at B");
                regCheckMask(B_c, RegEvents_c, x"00000080", x"00000080", "B: received codes ignored");
                regCheck(B_c, RegTimeCode_c, x"00000000", "no time-code register at B");
            end if;

        end loop;

        owrTestEnd(runner);
    end process;

    i_th : entity work.owr_core_th
        generic map (
            ServicesB_g => ServicesB_g
        )
        port map (
            Rst      => Rst,
            BcInA    => BcInA,
            BcInB    => BcInB,
            ObsA     => ObsA,
            ObsB     => ObsB,
            UserClkA => UserClkA,
            UserClkB => UserClkB,
            LinkClkA => LinkClkA,
            LinkMode => LinkMode,
            Cut      => Cut,
            Glitch   => Glitch
        );

end architecture;
