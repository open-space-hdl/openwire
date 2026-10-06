---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of owr_pkg: functions of the package, owr_cc_pulse and the self test of the
-- Data-Strobe far-end model.
--
-- Documentation: hdl/owr_pkg/docs/verification_plan.md

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
    use work.owr_tb_farend_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_pkg_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_pkg_tb is

    signal ClkA     : std_logic;
    signal ClkB     : std_logic;
    signal Rst      : std_logic                    := '1';
    signal PulseIn  : std_logic_vector(1 downto 0) := "00";
    signal PulseOut : std_logic_vector(1 downto 0);
    signal OutCnt0  : natural                      := 0;
    signal OutCnt1  : natural                      := 0;
    signal OutWidth : natural                      := 0;

begin

    test_runner_watchdog(runner, 10 ms);

    p_main : process is
        variable Ref_v  : TbChar_t;
        variable Got_v  : TbChar_t;
        variable Seq_v  : natural;
        variable Edge_v : TbEdge_t;
        variable Cnt_v  : natural;

        procedure checkChars (
            first : natural;
            seq   : natural;
            n     : natural) is
            variable Exp_v : TbChar_t;
            variable Act_v : TbChar_t;
        begin

            for i in 0 to n - 1 loop

                case (seq + i) mod 7 is
                    when 0 => Exp_v := tbData(seq + i);
                    when 1 => Exp_v := tbChar(TbFct);
                    when 2 => Exp_v := tbTimeCode(seq + i);
                    when 3 => Exp_v := tbChar(TbEop);
                    when 4 => Exp_v := tbInterrupt(seq + i);
                    when 5 => Exp_v := tbChar(TbEep);
                    when others => Exp_v := tbIntAck(seq + i);
                end case;

                Act_v := FarEnd_v.rxGet(1, first + i);
                check_value(Act_v.Kind = Exp_v.Kind, error, "kind of character " & to_string(i) & ": " &
                            tbKindStr(Act_v.Kind));
                check_value(Act_v.Data, Exp_v.Data, error, "data of character " & to_string(i));
            end loop;

        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        test_runner_setup(runner, runner_cfg);
        disable_log_msg(ID_POS_ACK);

        while test_suite loop

            Rst <= '1';
            wait for 100 ns;
            Rst <= '0';
            wait for 100 ns;

            if run("test_functions") then
                -- TC-PKG-01
                check_value(timeCycles(TimeErrorReset_c, 100.0e6), 640, error, "6.4 us at 100 MHz");
                check_value(timeCycles(TimeErrorWait_c, 200.0e6), 2560, error, "12.8 us at 200 MHz");
                check_value(timeCycles(TimeDisconnect_c, 100.0e6), 85, error, "850 ns at 100 MHz");
                check_value(initDivider(100.0e6), 10, error, "initial divider at 100 MHz");
                check_value(initDivider(125.0e6), 13, error, "initial divider at 125 MHz (9.6 Mb/s)");
                check_value(initDivider(200.0e6), 20, error, "initial divider at 200 MHz");
                check_value(xorReduce(x"5C"), '0', error, "xorReduce 0x5C");
                check_value(xorReduce(x"5D"), '1', error, "xorReduce 0x5D");
                -- ECSS Figure 5-15: data character 0x5C followed by a Null: parity bits 0 (ESC) and 0 (FCT)
                check_value(parityBit(xorReduce(x"5C"), '1'), '0', error, "parity of ESC after 0x5C");
                check_value(parityBit('0', '1'), '0', error, "parity of FCT after ESC");
                check_value(parityBit('0', '0'), '1', error, "parity of data character after ESC");
                -- Model encoding of the same sequence: 1 0 00111010 0111 0100 (first bit left)
                Ref_v := tbData(16#5C#);
                check_value(tbEncode(Ref_v, '0').Bits(9 downto 0), "0101110001", error,
                            "model encoding of data 0x5C (bit 0 first)");
                check_value(tbEncode(tbChar(TbNull), '0').Bits(7 downto 0), "00101110", error,
                            "model encoding of Null after 0x5C");

            elsif run("test_cc_pulse") then

                -- TC-PKG-02
                for i in 0 to 9 loop
                    wait until rising_edge(ClkA);
                    PulseIn <= std_logic_vector(to_unsigned(i mod 3 + 1, 2));
                    wait until rising_edge(ClkA);
                    PulseIn <= "00";
                    wait for 200 ns;
                end loop;

                check_value(OutCnt0, 7, error, "pulses of bit 0");
                check_value(OutCnt1, 6, error, "pulses of bit 1");
                check_value(OutWidth, 1, error, "maximum width of an output pulse");

            elsif run("test_ds_model") then
                -- TC-PKG-03
                FarEnd_v.rxClear(1);
                FarEnd_v.setBitPeriod(0, 20 ns);
                FarEnd_v.setMode(0, TbModeNull);
                wait for 1 us;
                -- First transition on the strobe line (ECSS 5.4.5)
                Edge_v := FarEnd_v.edgeGet(1, 0);
                check_value(Edge_v.D, '0', error, "data unchanged at the first edge");
                check_value(Edge_v.S, '1', error, "strobe changes at the first edge");
                check_value(FarEnd_v.rxKindCount(1, TbNull) > 0, error, "Nulls decoded");
                Seq_v  := 0;
                Cnt_v  := FarEnd_v.rxCount(1);

                for i in 0 to 699 loop

                    case i mod 7 is
                        when 0 => FarEnd_v.txPush(0, tbData(i));
                        when 1 => FarEnd_v.txPush(0, tbChar(TbFct));
                        when 2 => FarEnd_v.txPush(0, tbTimeCode(i));
                        when 3 => FarEnd_v.txPush(0, tbChar(TbEop));
                        when 4 => FarEnd_v.txPush(0, tbInterrupt(i));
                        when 5 => FarEnd_v.txPush(0, tbChar(TbEep));
                        when others => FarEnd_v.txPush(0, tbIntAck(i));
                    end case;

                end loop;

                tbWaitTxEmpty(0);
                wait for 1 us;
                check_value(FarEnd_v.rxCount(1) - Cnt_v, 700, error, "characters decoded");
                checkChars(Cnt_v, 0, 700);
                check_value(FarEnd_v.rxErrors(1), 0, error, "no decoding errors");
                -- No simultaneous transitions in the edge log
                Cnt_v := 0;

                for i in 1 to minimum(FarEnd_v.edgeCount(1), 8192) - 1 loop
                    if FarEnd_v.edgeGet(1, i).D /= FarEnd_v.edgeGet(1, i - 1).D and
                       FarEnd_v.edgeGet(1, i).S /= FarEnd_v.edgeGet(1, i - 1).S then
                        Cnt_v := Cnt_v + 1;
                    end if;
                end loop;

                check_value(Cnt_v, 0, error, "simultaneous transitions");

                -- Parity error: counted, decoder searches the next Null and continues
                FarEnd_v.txPush(0, tbChar(TbData, x"A5", true));
                tbWaitTxEmpty(0);
                wait for 2 us;
                check_value(FarEnd_v.rxErrors(1), 1, error, "parity error counted");
                Cnt_v := FarEnd_v.rxCount(1);
                FarEnd_v.txPush(0, tbData(16#11#));
                tbWaitTxEmpty(0);
                wait for 1 us;
                Got_v := FarEnd_v.rxGet(1, Cnt_v);
                check_value(Got_v.Kind = TbData, error, "data after resynchronisation");
                check_value(Got_v.Data, x"11", error, "data value after resynchronisation");

                -- ESC error: ESC followed by EOP
                FarEnd_v.txPush(0, tbChar(TbEsc));
                FarEnd_v.txPush(0, tbChar(TbEop));
                tbWaitTxEmpty(0);
                wait for 2 us;
                check_value(FarEnd_v.rxErrors(1), 2, error, "ESC error counted");

                -- Simultaneous transition
                FarEnd_v.requestSimultaneous(0);
                wait for 2 us;
                check_value(FarEnd_v.rxErrors(1), 3, error, "simultaneous transition counted");

                -- Silent mode and controlled reset: the decoder stops, a new first Null is found
                FarEnd_v.setMode(0, TbModeOff);
                wait for 3 us;
                Edge_v := FarEnd_v.edgeGet(1, FarEnd_v.edgeCount(1) - 1);
                check_value(Edge_v.D = '0' and Edge_v.S = '0', error, "data and strobe reset");
                FarEnd_v.setMode(0, TbModeNull);
                Cnt_v  := FarEnd_v.rxKindCount(1, TbNull);
                wait for 2 us;
                check_value(FarEnd_v.rxKindCount(1, TbNull) > Cnt_v, error, "Nulls after a restart");
            end if;

        end loop;

        owrTestEnd(runner);
    end process;

    -- Output pulse counters
    p_count : process (ClkB) is
        variable Width_v : natural := 0;
    begin
        if rising_edge(ClkB) then
            if PulseOut(0) = '1' then
                OutCnt0 <= OutCnt0 + 1;
            end if;
            if PulseOut(1) = '1' then
                OutCnt1 <= OutCnt1 + 1;
            end if;
            if PulseOut /= "00" then
                Width_v := Width_v + 1;
                if Width_v > OutWidth then
                    OutWidth <= Width_v;
                end if;
            else
                Width_v := 0;
            end if;
        end if;
    end process;

    i_th : entity work.owr_pkg_th
        port map (
            ClkA     => ClkA,
            ClkB     => ClkB,
            Rst      => Rst,
            PulseIn  => PulseIn,
            PulseOut => PulseOut
        );

end architecture;
