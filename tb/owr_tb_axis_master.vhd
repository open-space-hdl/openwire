---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- UVVM AXI-Stream master VVC with plain valid / ready stream ports, so that test harnesses connect
-- DUT streams without the t_axistream_if record boilerplate. Commands: axistream_transmit with
-- AXISTREAM_VVCT and InstanceIdx_g.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library bitvis_vip_axistream;
    use bitvis_vip_axistream.axistream_bfm_pkg.all;

library work;
    use work.owr_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_tb_axis_master is
    generic (
        InstanceIdx_g : natural;
        DataWidth_g   : positive;
        UserWidth_g   : positive := 1
    );
    port (
        Clk       : in    std_logic;
        Out_Data  : out   std_logic_vector(DataWidth_g-1 downto 0);
        Out_User  : out   std_logic_vector(UserWidth_g-1 downto 0);
        Out_Keep  : out   std_logic_vector(DataWidth_g/8-1 downto 0);
        Out_Last  : out   std_logic;
        Out_Valid : out   std_logic;
        Out_Ready : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_tb_axis_master is

    signal AxisIf : t_axistream_if(
                                    tdata(DataWidth_g-1 downto 0),
                                    tkeep(DataWidth_g/8-1 downto 0),
                                    tuser(UserWidth_g-1 downto 0),
                                    tstrb(DataWidth_g/8-1 downto 0),
                                    tid(0 downto 0),
                                    tdest(0 downto 0));

    -- Generator of long packets (owr_tb_pkg.OwrLongTx)
    signal LongActive : std_logic                                := '0';
    signal LongData   : std_logic_vector(DataWidth_g-1 downto 0) := (others => '0');
    signal LongLast   : std_logic                                := '0';
    signal LongValid  : std_logic                                := '0';

begin

    -- Signals driven by the DUT side
    AxisIf.tready <= Out_Ready and not LongActive;

    Out_Data  <= LongData when LongActive = '1' else AxisIf.tdata;
    Out_User  <= AxisIf.tuser;
    Out_Keep  <= AxisIf.tkeep;
    Out_Last  <= LongLast when LongActive = '1' else AxisIf.tlast;
    Out_Valid <= LongValid when LongActive = '1' else AxisIf.tvalid;

    -- One counting packet per toggle of Start, one beat per accepted cycle, then the end of packet marker
    p_long : process is
        variable Req_v : OwrLongPkt_t;
    begin
        wait on OwrLongTx(InstanceIdx_g).Start;
        Req_v      := OwrLongTx(InstanceIdx_g);
        wait until rising_edge(Clk);
        LongActive <= '1';

        for i in 0 to Req_v.Length loop
            if i < Req_v.Length then
                LongData <= std_logic_vector(to_unsigned((Req_v.First + i) mod 256, DataWidth_g));
                LongLast <= '0';
            else
                LongData <= (others => '0');
                if Req_v.Eep then
                    LongData(0) <= '1';
                end if;
                LongLast <= '1';
            end if;
            LongValid <= '1';

            loop
                wait until rising_edge(Clk);
                exit when Out_Ready = '1';
            end loop;

        end loop;

        LongValid                  <= '0';
        LongActive                 <= '0';
        OwrLongDone(InstanceIdx_g) <= OwrLongDone(InstanceIdx_g) + 1;
    end process;

    i_vvc : entity bitvis_vip_axistream.axistream_vvc
        generic map (
            Gc_Vvc_Is_Master        => true,
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
