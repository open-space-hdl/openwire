---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- UVVM AXI-Stream slave VVC with plain valid / ready stream ports, so that test harnesses connect
-- DUT streams without the t_axistream_if record boilerplate. Commands: axistream_expect and
-- axistream_receive with AXISTREAM_VVCT and InstanceIdx_g.
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
    use bitvis_vip_axistream.vvc_methods_pkg.all;

library work;
    use work.owr_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_tb_axis_slave is
    generic (
        InstanceIdx_g              : natural;
        DataWidth_g                : positive;
        UserWidth_g                : positive      := 1;
        -- Alert when the DUT drives the stream while no command is active (UVVM unwanted activity)
        UnwantedActivitySeverity_g : t_alert_level := NO_ALERT
    );
    port (
        Clk      : in    std_logic;
        In_Data  : in    std_logic_vector(DataWidth_g-1 downto 0);
        In_User  : in    std_logic_vector(UserWidth_g-1 downto 0)   := (others => '0');
        In_Keep  : in    std_logic_vector(DataWidth_g/8-1 downto 0) := (others => '1');
        In_Last  : in    std_logic                                  := '0';
        In_Valid : in    std_logic;
        In_Ready : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_tb_axis_slave is

    signal AxisIf : t_axistream_if(
                                    tdata(DataWidth_g-1 downto 0),
                                    tkeep(DataWidth_g/8-1 downto 0),
                                    tuser(UserWidth_g-1 downto 0),
                                    tstrb(DataWidth_g/8-1 downto 0),
                                    tid(0 downto 0),
                                    tdest(0 downto 0));

    -- Checker of long packets (owr_tb_pkg.OwrLongRx)
    signal LongActive : std_logic := '0';

begin

    -- Signals driven by the DUT side
    AxisIf.tdata  <= In_Data;
    AxisIf.tuser  <= In_User;
    AxisIf.tkeep  <= In_Keep;
    AxisIf.tlast  <= In_Last;
    AxisIf.tvalid <= In_Valid and not LongActive;
    AxisIf.tstrb  <= (others => '0');
    AxisIf.tid    <= (others => '0');
    AxisIf.tdest  <= (others => '0');

    In_Ready <= '1' when LongActive = '1' else AxisIf.tready;

    -- One counting packet per toggle of Start: every data byte and the end of packet marker are checked; in prefix
    -- mode a shorter packet ended by an EEP is accepted. The number of data bytes goes to OwrLongBytes.
    p_long : process is
        variable Req_v : OwrLongPkt_t;
        variable N_v   : natural;
        variable Ok_v  : boolean;
    begin
        wait on OwrLongRx(InstanceIdx_g).Start;
        Req_v      := OwrLongRx(InstanceIdx_g);
        N_v        := 0;
        Ok_v       := true;
        LongActive <= '1';

        loop
            wait until rising_edge(Clk);
            if In_Valid = '1' then
                exit when In_Last = '1';
                if Ok_v and In_Data(7 downto 0) /= std_logic_vector(to_unsigned((Req_v.First + N_v) mod 256, 8)) then
                    alert(error, "long packet: data byte " & to_string(N_v) & " is " & to_hstring(In_Data(7 downto 0)));
                    Ok_v := false;
                end if;
                N_v := N_v + 1;
            end if;
        end loop;

        if Req_v.Prefix then
            check_value(N_v <= Req_v.Length and In_Data(0) = '1', error,
                        "long packet: prefix of " & to_string(N_v) & " bytes ended by an EEP");
        else
            check_value(N_v, Req_v.Length, error, "long packet: data bytes");
            check_value(In_Data(0) = '1', Req_v.Eep, error, "long packet: EEP marker");
        end if;
        LongActive                  <= '0';
        OwrLongBytes(InstanceIdx_g) <= N_v;
        OwrLongDone(InstanceIdx_g)  <= OwrLongDone(InstanceIdx_g) + 1;
    end process;

    p_config : process is
    begin
        wait for 1 ns; -- after the VVC constructor
        shared_axistream_vvc_config(InstanceIdx_g).unwanted_activity_severity := UnwantedActivitySeverity_g;
        wait;
    end process;

    i_vvc : entity bitvis_vip_axistream.axistream_vvc
        generic map (
            Gc_Vvc_Is_Master        => false,
            Gc_Data_Width           => DataWidth_g,
            Gc_User_Width           => UserWidth_g,
            Gc_Id_Width             => 1,
            Gc_Dest_Width           => 1,
            Gc_Instance_Idx         => InstanceIdx_g,
            Gc_Axistream_Bfm_Config => OwrAxisBfmConfig_c
        )
        port map (
            Clk              => Clk,
            Axistream_Vvc_If => AxisIf
        );

end architecture;
