---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the MIB: register map over AXI4-Lite, configuration outputs, commands, status,
-- sticky flags, counters, interrupt, EDAC monitor and error injection, register bridge.
--
-- Documentation: hdl/owr_mib/docs/verification_plan.md

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

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.owr_pkg.all;
    use work.owr_regs_pkg.all;
    use work.owr_tb_pkg.all;
    use work.owr_mib_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_mib_tb is
    generic (
        runner_cfg    : string;
        MgmtHalfPs_g  : positive := 3000
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_mib_tb is

    signal LinkClk : std_logic;
    signal UserClk : std_logic;
    signal MgmtClk : std_logic;
    signal Rst     : std_logic := '1';
    signal MibIn   : MibIn_t   := MibInInit_c;
    signal MibOut  : MibOut_t;

begin

    test_runner_watchdog(runner, 10 ms);

    p_main : process is
        variable Data_v : std_logic_vector(31 downto 0);

        procedure regWrite (
            addr : natural;
            data : std_logic_vector(31 downto 0)) is
        begin
            axilite_write(AXILITE_VVCT, Axi_c, to_unsigned(addr, 8), data, "write 0x" & to_hstring(to_unsigned(addr, 8)));
            await_completion(AXILITE_VVCT, Axi_c, 100 us);
        end procedure;

        procedure regCheck (
            addr : natural;
            data : std_logic_vector(31 downto 0);
            msg  : string) is
        begin
            axilite_check(AXILITE_VVCT, Axi_c, to_unsigned(addr, 8), data, msg);
            await_completion(AXILITE_VVCT, Axi_c, 100 us);
        end procedure;

        -- One-cycle event pulse on input bit n in LinkClk
        procedure event (n : natural) is
        begin
            wait until rising_edge(LinkClk);
            MibIn.Ev(n) <= '1';
            wait until rising_edge(LinkClk);
            MibIn.Ev(n) <= '0';
        end procedure;

        -- ECC event: kind 0 SEC, 1 DED; fifo 0 Tx, 1 Rx, 2 BcReq, 3 BcInd
        procedure eccEvent (
            fifo : natural;
            kind : natural) is
        begin

            case fifo is

                when 0 =>
                    wait until rising_edge(LinkClk);
                    MibIn.EccTx(kind) <= '1';
                    wait until rising_edge(LinkClk);
                    MibIn.EccTx(kind) <= '0';

                when 1 =>
                    wait until rising_edge(UserClk);
                    MibIn.EccRx(kind) <= '1';
                    wait until rising_edge(UserClk);
                    MibIn.EccRx(kind) <= '0';

                when 2 =>
                    wait until rising_edge(LinkClk);
                    MibIn.EccBcReq(kind) <= '1';
                    wait until rising_edge(LinkClk);
                    MibIn.EccBcReq(kind) <= '0';

                when others =>
                    wait until rising_edge(UserClk);
                    MibIn.EccBcInd(kind) <= '1';
                    wait until rising_edge(UserClk);
                    MibIn.EccBcInd(kind) <= '0';

            end case;

            wait for 200 ns;
        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);
        await_uvvm_initialization(VOID);
        disable_log_msg(AXILITE_VVCT, Axi_c, ALL_MESSAGES);

        while test_suite loop

            Rst <= '1';
            wait for 100 ns;
            wait until rising_edge(LinkClk);
            Rst <= '0';
            wait for 200 ns;

            if run("test_reset_values") then
                -- TC-MG-01
                regCheck(RegId_c, RegMapId_c, "ID");
                regCheck(RegGenerics_c, x"00001003", "generics");
                regCheck(RegFifoDepths_c, x"00800040", "FIFO depths");
                regCheck(RegClkFreq_c, std_logic_vector(to_unsigned(100000, 32)), "clock frequency in kHz");
                regCheck(RegPortCtrl_c, x"00000034", "PORT_CTRL from the generics");
                regCheck(RegLinkSpeed_c, x"00000A04", "LINK_SPEED: run divider 4, initial divider 10");
                regCheck(RegErrors_c, RegErrorsReset_c, "ERRORS");
                regCheck(RegErrorCounts_c, RegErrorCountsReset_c, "ERROR_COUNTS");
                regCheck(RegLinkCounts_c, RegLinkCountsReset_c, "LINK_COUNTS");
                regCheck(RegEvents_c, RegEventsReset_c, "EVENTS");
                regCheck(RegErrorsIrqEn_c, RegErrorsIrqEnReset_c, "ERRORS_IRQ_EN");
                regCheck(RegEventsIrqEn_c, RegEventsIrqEnReset_c, "EVENTS_IRQ_EN");
                regCheck(RegTcSend_c, RegTcSendReset_c, "TC_SEND reads zero");
                regCheck(RegTcCounts_c, RegTcCountsReset_c, "TC_COUNTS");
                regCheck(RegIntCtrl_c, RegIntCtrlReset_c, "INT_CTRL");
                regCheck(RegIntTick_c, x"00000064", "INT_TICK 1 us");
                regCheck(RegIntHoldoff_c, x"00000000", "INT_HOLDOFF");
                regCheck(RegIntAckDelay_c, x"00000000", "INT_ACK_DELAY");
                regCheck(RegIntSend_c, RegIntSendReset_c, "INT_SEND reads zero");
                regCheck(RegIntAck_c, RegIntAckReset_c, "INT_ACK reads zero");
                regCheck(RegAckReceived_c, RegAckReceivedReset_c, "ACK_RECEIVED");
                regCheck(RegEccStatus_c, RegEccStatusReset_c, "ECC_STATUS");
                regCheck(RegEccSelect_c, RegEccSelectReset_c, "ECC_SELECT");
                regCheck(RegEccCount_c, RegEccCountReset_c, "ECC_COUNT");
                regCheck(RegEccInject_c, RegEccInjectReset_c, "ECC_INJECT reads zero");
                regCheck(16#F0#, x"00000000", "unused address reads zero");
                check_value(MibOut.LinkStart, '1', error, "LinkStart output");
                check_value(MibOut.LinkDisabled, '0', error, "LinkDisabled output");
                check_value(MibOut.RunDiv, x"04", error, "run divider output");
                check_value(MibOut.DriverEn and MibOut.ReceiverEn, '1', error, "driver and receiver enabled");
                check_value(MibOut.Irq, '0', error, "no interrupt");

            elsif run("test_config_registers") then
                -- TC-MG-02
                regWrite(RegPortCtrl_c, x"0000004A");
                regCheck(RegPortCtrl_c, x"0000004A", "PORT_CTRL");
                wait for 100 ns;
                check_value(MibOut.LinkDisabled, '1', error, "LinkDisabled");
                check_value(MibOut.LinkStart, '0', error, "LinkStart");
                check_value(MibOut.AutoStart, '1', error, "AutoStart");
                check_value(MibOut.DriverEn, '0', error, "driver enable");
                check_value(MibOut.ReceiverEn, '0', error, "receiver enable");
                check_value(MibOut.Loopback, '1', error, "loopback");
                regWrite(RegLinkSpeed_c, x"000000C8");
                regCheck(RegLinkSpeed_c, x"00000AC8", "LINK_SPEED (initial divider read only)");
                regWrite(RegIntCtrl_c, x"00000001");
                regWrite(RegIntTick_c, x"00001234");
                regWrite(RegIntHoldoff_c, x"0000ABCD");
                regWrite(RegIntAckDelay_c, x"00004321");
                regWrite(RegErrorsIrqEn_c, x"0000000F");
                regWrite(RegEventsIrqEn_c, x"00003FFF");
                regWrite(RegEccSelect_c, x"00000005");
                regCheck(RegIntCtrl_c, x"00000001", "INT_CTRL");
                regCheck(RegIntTick_c, x"00001234", "INT_TICK");
                regCheck(RegIntHoldoff_c, x"0000ABCD", "INT_HOLDOFF");
                regCheck(RegIntAckDelay_c, x"00004321", "INT_ACK_DELAY");
                regCheck(RegErrorsIrqEn_c, x"0000000F", "ERRORS_IRQ_EN");
                regCheck(RegEventsIrqEn_c, x"00003FFF", "EVENTS_IRQ_EN");
                regCheck(RegEccSelect_c, x"00000005", "ECC_SELECT");
                wait for 100 ns;
                check_value(MibOut.RunDiv, x"C8", error, "run divider output");
                check_value(MibOut.AckMode, '1', error, "acknowledgement mode output");
                check_value(MibOut.IntTick, x"1234", error, "tick output");
                check_value(MibOut.IntHoldoff, x"ABCD", error, "minimum interval output");
                check_value(MibOut.AckDelay, x"4321", error, "acknowledgement delay output");
                -- Read-only registers ignore writes
                regWrite(RegId_c, x"FFFFFFFF");
                regCheck(RegId_c, RegMapId_c, "ID after a write");

            elsif run("test_commands") then
                -- TC-MG-03
                regWrite(RegPortCtrl_c, x"00000035");
                wait for 100 ns;
                check_value(MibOut.CntPortReset, 1, error, "port reset pulse");
                regCheck(RegPortCtrl_c, x"00000034", "PORT_RESET reads zero");
                regWrite(RegTcSend_c, x"0000002A");
                regWrite(RegIntSend_c, x"00000011");
                regWrite(RegIntAck_c, x"00000017");
                wait for 100 ns;
                check_value(MibOut.CntTc, 1, error, "TIME-CODE.request");
                check_value(MibOut.LastTc, "101010", error, "time-code value");
                check_value(MibOut.CntInt, 1, error, "DISTRIBUTED_INTERRUPT.request");
                check_value(MibOut.LastInt, "10001", error, "interrupt identifier");
                check_value(MibOut.CntAck, 1, error, "DISTRIBUTED_INTERRUPT_ACK.request");
                check_value(MibOut.LastAck, "10111", error, "acknowledgement identifier");
                regCheck(RegTcSend_c, x"00000000", "TC_SEND reads zero");

            elsif run("test_status_registers") then
                -- TC-MG-04
                MibIn.State     <= StateRun_c;
                MibIn.Recovery  <= '1';
                MibIn.GotNull   <= '1';
                MibIn.Spill     <= '1';
                MibIn.Cause     <= CauseCredit_c;
                MibIn.TxCredit  <= "101010";
                MibIn.RxCredit  <= "110000";
                MibIn.TxLevel   <= x"0021";
                MibIn.RxLevel   <= x"0080";
                MibIn.TimeCode  <= "111001";
                MibIn.IntActive <= x"80010002";
                wait for 100 ns;
                regCheck(RegPortStatus_c, x"0000053D", "PORT_STATUS");
                regCheck(RegCredit_c, x"0000302A", "CREDIT");
                regCheck(RegFifoLevels_c, x"00800021", "FIFO_LEVELS");
                regCheck(RegTimeCode_c, x"00000039", "TIME_CODE");
                regCheck(RegIntActive_c, x"80010002", "INT_ACTIVE");

            elsif run("test_flags") then

                -- TC-MG-05
                for i in 0 to 13 loop
                    if i /= 7 then
                        event(i);
                    end if;
                end loop;

                MibIn.AckIid <= "00110";
                event(7);
                MibIn.AckIid <= "11111";
                event(7);
                regCheck(RegErrors_c, x"0000000F", "all error flags");
                regCheck(RegEvents_c, x"00000FFC", "event flags of the inputs");
                regCheck(RegAckReceived_c, x"80000040", "acknowledgements received");
                -- Link up and down from the link state
                MibIn.State <= StateRun_c;
                wait for 100 ns;
                MibIn.State <= StateErrorReset_c;
                wait for 100 ns;
                regCheck(RegEvents_c, x"00000FFF", "link up and down");
                -- Write one to clear only the written bits
                regWrite(RegErrors_c, x"00000005");
                regCheck(RegErrors_c, x"0000000A", "ERRORS after clearing bits 0 and 2");
                regWrite(RegEvents_c, x"00000FF0");
                regCheck(RegEvents_c, x"0000000F", "EVENTS after clearing bits 4 to 11");
                regWrite(RegAckReceived_c, x"80000000");
                regCheck(RegAckReceived_c, x"00000040", "ACK_RECEIVED after clearing bit 31");

            elsif run("test_counters") then

                -- TC-MG-06
                for i in 1 to 300 loop
                    event(0);
                end loop;

                for i in 1 to 3 loop
                    event(1);
                    event(2);
                end loop;

                event(3);

                for i in 1 to 7 loop
                    event(4);
                end loop;

                event(5);
                event(5);
                regCheck(RegErrorCounts_c, x"010303FF", "error counters, disconnect saturated at 255");
                regCheck(RegTcCounts_c, x"00020007", "time-code counters");

                for i in 1 to 4 loop
                    MibIn.State    <= StateRun_c;
                    wait for 100 ns;
                    MibIn.State    <= StateErrorReset_c;
                    MibIn.Recovery <= '1';
                    wait for 100 ns;
                    MibIn.Recovery <= '0';
                end loop;

                regCheck(RegLinkCounts_c, x"00040004", "Run entries and recoveries");
                regWrite(RegErrorCounts_c, x"00000000");
                regWrite(RegTcCounts_c, x"00000000");
                regWrite(RegLinkCounts_c, x"00000000");
                regCheck(RegErrorCounts_c, x"00000000", "error counters cleared");
                regCheck(RegTcCounts_c, x"00000000", "time-code counters cleared");
                regCheck(RegLinkCounts_c, x"00000000", "link counters cleared");

            elsif run("test_irq") then
                -- TC-MG-07
                event(1);
                event(6);
                wait for 200 ns;
                check_value(MibOut.Irq, '0', error, "no interrupt while disabled");
                regWrite(RegErrorsIrqEn_c, x"00000002");
                wait for 200 ns;
                check_value(MibOut.Irq, '1', error, "interrupt by the parity error flag");
                regCheck(RegIrqStatus_c, x"00000001", "IRQ_STATUS");
                regWrite(RegErrors_c, x"00000002");
                wait for 200 ns;
                check_value(MibOut.Irq, '0', error, "interrupt cleared with the flag");
                regWrite(RegEventsIrqEn_c, x"00000010");
                wait for 200 ns;
                check_value(MibOut.Irq, '1', error, "interrupt by the interrupt-received flag");
                regWrite(RegEventsIrqEn_c, x"00000000");
                wait for 200 ns;
                check_value(MibOut.Irq, '0', error, "interrupt disabled");

            elsif run("test_ecc") then
                -- TC-MG-08
                -- Events of the four FIFOs of the Data Link and Network layers
                eccEvent(0, 0);
                eccEvent(0, 0);
                eccEvent(1, 0);
                eccEvent(1, 1);
                eccEvent(2, 1);
                eccEvent(3, 0);
                eccEvent(3, 0);
                eccEvent(3, 0);
                regCheck(RegEccStatus_c, x"00000006", "DED flags of channels 1 and 2");
                regWrite(RegEccSelect_c, x"00000000");
                regCheck(RegEccCount_c, x"00000002", "channel 0: two SEC");
                regWrite(RegEccSelect_c, x"00000001");
                regCheck(RegEccCount_c, x"00010001", "channel 1: SEC and DED");
                regWrite(RegEccSelect_c, x"00000003");
                regCheck(RegEccCount_c, x"00000003", "channel 3: three SEC");
                regCheck(RegEvents_c, x"00003000", "ECC event flags");
                -- Read and clear of one channel, then global clear
                regWrite(RegEccCount_c, x"00000000");
                regCheck(RegEccCount_c, x"00000000", "channel 3 cleared");
                regWrite(RegEccSelect_c, x"00000000");
                regCheck(RegEccCount_c, x"00000002", "channel 0 kept");
                regWrite(RegEccStatus_c, x"00000000");
                regCheck(RegEccCount_c, x"00000000", "channel 0 cleared globally");
                regCheck(RegEccStatus_c, x"00000000", "DED flags cleared");
                -- Injection commands into the write sides
                regWrite(RegEccInject_c, x"00000100");
                regWrite(RegEccInject_c, x"00000201");
                regWrite(RegEccInject_c, x"00000102");
                regWrite(RegEccInject_c, x"00000203");
                -- Neither SINGLE nor DOUBLE: no injection
                regWrite(RegEccInject_c, x"00000000");
                wait for 500 ns;
                check_value(MibOut.CntInjTx, 1, error, "injection into the transmit FIFO (UserClk)");
                check_value(MibOut.BitsInjTx, 1, error, "single error");
                check_value(MibOut.CntInjRx, 1, error, "injection into the receive FIFO (LinkClk)");
                check_value(MibOut.BitsInjRx, 2, error, "double error");
                check_value(MibOut.CntInjBcReq, 1, error, "injection into the broadcast request FIFO");
                check_value(MibOut.BitsInjBcReq, 1, error, "single error");
                check_value(MibOut.CntInjBcInd, 1, error, "injection into the broadcast indication FIFO");
                check_value(MibOut.BitsInjBcInd, 2, error, "double error");
                -- Register request FIFO: single error corrected, double error drops the access
                regWrite(RegEccInject_c, x"00000104");
                wait for 500 ns;
                regWrite(RegIntTick_c, x"00000077");
                regCheck(RegIntTick_c, x"00000077", "write with a corrected single error");
                regWrite(RegEccInject_c, x"00000204");
                wait for 500 ns;
                regWrite(RegIntTick_c, x"00000099");
                regCheck(RegIntTick_c, x"00000077", "write with a double error dropped");
                regWrite(RegEccSelect_c, x"00000004");
                regCheck(RegEccCount_c, x"00010001", "channel 4: SEC and DED");
                -- Register response FIFO: single error corrected, double error lets the read time out
                regWrite(RegEccInject_c, x"00000105");
                regCheck(RegIntTick_c, x"00000077", "read with a corrected single error");
                regWrite(RegEccInject_c, x"00000205");
                shared_axilite_vvc_config(Axi_c).bfm_config.expected_response_severity := ERROR;
                shared_axilite_vvc_config(Axi_c).bfm_config.max_wait_cycles            := 5000;
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                axilite_read(AXILITE_VVCT, Axi_c, to_unsigned(RegIntTick_c, 8), "read with a double error");
                await_completion(AXILITE_VVCT, Axi_c, 100 us);
                shared_axilite_vvc_config(Axi_c).bfm_config.expected_response_severity := TB_FAILURE;
                regWrite(RegEccSelect_c, x"00000005");
                regCheck(RegEccCount_c, x"00010001", "channel 5: SEC and DED");
                regCheck(RegEccStatus_c, x"00000030", "DED flags of channels 4 and 5");

            elsif run("test_read_after_write") then

                -- TC-MG-09
                -- AXI4-Lite does not order reads and writes; the read is issued when the write is complete
                for i in 0 to 49 loop
                    Data_v := std_logic_vector(to_unsigned(i * 977 mod 65536, 32));
                    axilite_write(AXILITE_VVCT, Axi_c, to_unsigned(RegIntTick_c, 8), Data_v, "write");
                    await_completion(AXILITE_VVCT, Axi_c, 100 us);
                    axilite_check(AXILITE_VVCT, Axi_c, to_unsigned(RegIntTick_c, 8), Data_v, "read after write");
                end loop;

                await_completion(AXILITE_VVCT, Axi_c, 1 ms);

                -- Back-to-back writes of commands are all executed (with the fastest management clock they fill the
                -- request FIFO and the bridge holds the write channels)
                for i in 0 to 59 loop
                    axilite_write(AXILITE_VVCT, Axi_c, to_unsigned(RegTcSend_c, 8),
                                  std_logic_vector(to_unsigned(i, 32)), "time-code request");
                end loop;

                await_completion(AXILITE_VVCT, Axi_c, 1 ms);
                wait for 1 us;
                check_value(MibOut.CntTc, 60, error, "every command executed");
                check_value(MibOut.LastTc, "111011", error, "last time-code value");
            end if;

        end loop;

        owrTestEnd(runner);
    end process;

    i_th : entity work.owr_mib_th
        generic map (
            MgmtHalfPeriod_g => MgmtHalfPs_g * 1 ps
        )
        port map (
            LinkClk => LinkClk,
            UserClk => UserClk,
            MgmtClk => MgmtClk,
            Rst     => Rst,
            MibIn   => MibIn,
            MibOut  => MibOut
        );

end architecture;
