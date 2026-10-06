---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Time-code service of a SpaceWire node (NI-2): time-code register, TIME-CODE.request and the check
-- of received time-codes (ECSS-E-ST-50-12C Rev.1 clause 5.6.4).
--
-- Documentation: hdl/owr_ni/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_ni_tc is
    port (
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        Cfg_PortReset : in    std_logic;
        -- TIME-CODE.request
        Req_Value     : in    std_logic_vector(5 downto 0);
        Req_Valid     : in    std_logic;
        -- Time-code to send, taken with Tx_Grant
        Tx_Value      : out   std_logic_vector(5 downto 0);
        Tx_Valid      : out   std_logic;
        Tx_Grant      : in    std_logic;
        -- Received time-code
        Rx_Value      : in    std_logic_vector(5 downto 0);
        Rx_Valid      : in    std_logic;
        -- TIME-CODE.indication of a valid time-code
        Ind_Value     : out   std_logic_vector(5 downto 0);
        Ind_Valid     : out   std_logic;
        -- Status
        Stat_Register : out   std_logic_vector(5 downto 0);
        Ev_Invalid    : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_ni_tc is

    type TwoProcess_r is record
        Reg     : unsigned(5 downto 0);
        Pending : std_logic;
        PendVal : std_logic_vector(5 downto 0);
        IndVal  : std_logic_vector(5 downto 0);
        Ind     : std_logic;
        Invalid : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v : TwoProcess_r;
    begin
        v         := r;
        v.Ind     := '0';
        v.Invalid := '0';

        -- Time-code taken by the Data Link layer
        if Tx_Grant = '1' then
            v.Pending := '0';
        end if;

        -- ECSS 5.6.4.4c: the time-code master loads the register with the value for sending
        if Req_Valid = '1' then
            v.Reg     := unsigned(Req_Value);
            v.Pending := '1';
            v.PendVal := Req_Value;
        end if;

        -- ECSS 5.6.4.5, 5.6.4.8, 5.6.4.9: valid when one more than the register modulo 64
        if Rx_Valid = '1' then
            if unsigned(Rx_Value) = r.Reg + 1 then
                v.Ind    := '1';
                v.IndVal := Rx_Value;
            else
                v.Invalid := '1';
            end if;
            v.Reg := unsigned(Rx_Value);
        end if;

        -- ECSS 5.6.4.3d
        if Cfg_PortReset = '1' then
            v.Reg     := (others => '0');
            v.Pending := '0';
        end if;

        r_next <= v;
    end process;

    Tx_Value      <= r.PendVal;
    Tx_Valid      <= r.Pending;
    Ind_Value     <= r.IndVal;
    Ind_Valid     <= r.Ind;
    Stat_Register <= std_logic_vector(r.Reg);
    Ev_Invalid    <= r.Invalid;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.Reg     <= (others => '0');
                r.Pending <= '0';
                r.Ind     <= '0';
                r.Invalid <= '0';
            end if;
        end if;
    end process;

end architecture;
