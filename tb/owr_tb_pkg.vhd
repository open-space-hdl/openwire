---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Verification helpers shared by all OpenWire testbenches (VUnit runner plus UVVM).
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library bitvis_vip_axistream;
    use bitvis_vip_axistream.axistream_bfm_pkg.all;

library vunit_lib;
    context vunit_lib.vunit_run_context;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package owr_tb_pkg is

    -- AXI-Stream BFM configuration of the OpenWire testbenches: element bits map 1:1 to TDATA
    -- (LOWER_BYTE_RIGHT) and the timeouts suit link latencies.
    constant OwrAxisBfmConfig_c : t_axistream_bfm_config := (
        max_wait_cycles                => 1000000,
        max_wait_cycles_severity       => error,
        clock_period                   => C_UNDEFINED_TIME,
        clock_period_margin            => 0 ns,
        clock_margin_severity          => TB_ERROR,
        setup_time                     => C_UNDEFINED_TIME,
        hold_time                      => C_UNDEFINED_TIME,
        bfm_sync                       => SYNC_ON_CLOCK_ONLY,
        match_strictness               => MATCH_EXACT,
        byte_endianness                => LOWER_BYTE_RIGHT,
        valid_low_at_word_num          => 0,
        valid_low_multiple_random_prob => 0.5,
        valid_low_duration             => 0,
        valid_low_max_random_duration  => 5,
        check_packet_length            => false,
        protocol_error_severity        => error,
        ready_low_at_word_num          => 0,
        ready_low_multiple_random_prob => 0.5,
        ready_low_duration             => 0,
        ready_low_max_random_duration  => 5,
        ready_default_value            => '0',
        id_for_bfm                     => ID_BFM
    );

    -- Ends a test: prints the UVVM alert summary, raises a TB_ERROR when an unexpected alert occurred
    -- or an expected alert did not occur (this stops the simulation and fails the VUnit test) and
    -- hands over to the VUnit runner.
    procedure owrTestEnd (signal runner : inout runner_sync_t);

    -- Packet of data bytes followed by its end of packet marker (0x00 EOP, 0x01 EEP) as the byte array of the
    -- AXI4-Stream VVCs: the last element is the marker beat with TLast set.
    function owrPacket (
        data : in t_slv_array;
        eep  : in boolean := false) return t_slv_array;

    -- Packet of n bytes with the values (first + i) mod 256
    function owrCountPacket (
        n     : in natural;
        first : in natural := 0;
        eep   : in boolean := false) return t_slv_array;

    -- Long packets: the AXI4-Stream VVC carries at most 16 KiB per command, so owr_tb_axis_master generates and
    -- owr_tb_axis_slave checks a packet of owrCountPacket values of any length itself, while its VVC is idle. The
    -- arrays are indexed by the VVC instance; the test toggles Start.
    type OwrLongPkt_t is record
        Start  : boolean; -- toggled by the test
        Length : natural; -- data bytes
        First  : natural; -- value of the first data byte
        Eep    : boolean; -- end of packet marker: EEP (generator) or expected EEP (checker)
        Prefix : boolean; -- checker: a prefix of the packet ended by an EEP is accepted
    end record;

    type OwrLongPktArr_t is array (natural range <>) of OwrLongPkt_t;

    constant OwrLongPktIdle_c : OwrLongPkt_t := (Start => false, Length => 0, First => 0, Eep => false,
                                                 Prefix => false);

    signal OwrLongTx : OwrLongPktArr_t(0 to 15) := (others => OwrLongPktIdle_c);
    signal OwrLongRx : OwrLongPktArr_t(0 to 15) := (others => OwrLongPktIdle_c);

    -- Completed packets and data bytes of the last packet per VVC instance, written by the components: every
    -- element has one writer, the maximum resolves the drivers of the other components
    function owrMaxInt (values : integer_vector) return integer;

    subtype OwrMaxInt_t is owrMaxInt integer;

    type OwrMaxIntArr_t is array (natural range <>) of OwrMaxInt_t;

    signal OwrLongDone  : OwrMaxIntArr_t(0 to 15) := (others => 0);
    signal OwrLongBytes : OwrMaxIntArr_t(0 to 15) := (others => 0);

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body owr_tb_pkg is

    procedure owrTestEnd (signal runner : inout runner_sync_t) is
    begin
        report_alert_counters(FINAL);
        if shared_uvvm_status.mismatch_on_expected_simulation_warnings_or_worse /= 0 then
            alert(TB_ERROR, "UVVM alert counters do not match the expected alerts", "owrTestEnd");
        end if;
        test_runner_cleanup(runner);
    end procedure;

    function owrPacket (
        data : in t_slv_array;
        eep  : in boolean := false) return t_slv_array is
        variable Arr_v : t_slv_array(0 to data'length)(7 downto 0);
    begin

        for i in 0 to data'length - 1 loop
            Arr_v(i) := data(data'low + i);
        end loop;

        if eep then
            Arr_v(data'length) := x"01";
        else
            Arr_v(data'length) := x"00";
        end if;
        return Arr_v;
    end function;

    function owrCountPacket (
        n     : in natural;
        first : in natural := 0;
        eep   : in boolean := false) return t_slv_array is
        variable Arr_v : t_slv_array(0 to n)(7 downto 0);
    begin

        for i in 0 to n - 1 loop
            Arr_v(i) := std_logic_vector(to_unsigned((first + i) mod 256, 8));
        end loop;

        if eep then
            Arr_v(n) := x"01";
        else
            Arr_v(n) := x"00";
        end if;
        return Arr_v;
    end function;

    function owrMaxInt (values : integer_vector) return integer is
        variable Max_v : integer := 0;
    begin

        for i in values'range loop
            if values(i) > Max_v then
                Max_v := values(i);
            end if;
        end loop;

        return Max_v;
    end function;

end package body;
