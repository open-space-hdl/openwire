---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Distributed interrupt service of a SpaceWire node (NI-3): interrupt register, interrupt and
-- acknowledgement codes in interrupt mode and interrupt with acknowledgement mode, minimum interval
-- between interrupt codes and minimum acknowledgement delay (ECSS-E-ST-50-12C Rev.1 clause 5.6.5).
--
-- Documentation: hdl/owr_ni/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_ni_int is
    generic (
        TimerWidth_g : positive range 1 to 30 := 16
    );
    port (
        Clk                : in    std_logic;
        Rst                : in    std_logic;
        Cfg_PortReset      : in    std_logic;
        -- Configuration
        Cfg_AckMode        : in    std_logic;
        Cfg_Tick           : in    std_logic_vector(15 downto 0);
        Cfg_Holdoff        : in    std_logic_vector(TimerWidth_g - 1 downto 0);
        Cfg_AckDelay       : in    std_logic_vector(TimerWidth_g - 1 downto 0);
        -- DISTRIBUTED_INTERRUPT.request and DISTRIBUTED_INTERRUPT_ACK.request
        IntReq_Iid         : in    std_logic_vector(4 downto 0);
        IntReq_Valid       : in    std_logic;
        AckReq_Iid         : in    std_logic_vector(4 downto 0);
        AckReq_Valid       : in    std_logic;
        -- Codes to send, taken with the grant (Tx_Discarded: discarded by the Data Link layer outside Run)
        TxInt_Iid          : out   std_logic_vector(4 downto 0);
        TxInt_Valid        : out   std_logic;
        TxInt_Grant        : in    std_logic;
        TxAck_Iid          : out   std_logic_vector(4 downto 0);
        TxAck_Valid        : out   std_logic;
        TxAck_Grant        : in    std_logic;
        Tx_Discarded       : in    std_logic;
        -- Received interrupt and acknowledgement codes
        RxInt_Iid          : in    std_logic_vector(4 downto 0);
        RxInt_Valid        : in    std_logic;
        RxAck_Iid          : in    std_logic_vector(4 downto 0);
        RxAck_Valid        : in    std_logic;
        -- Indications
        IndInt_Iid         : out   std_logic_vector(4 downto 0);
        IndInt_Valid       : out   std_logic;
        IndAck_Iid         : out   std_logic_vector(4 downto 0);
        IndAck_Valid       : out   std_logic;
        -- Status
        Stat_Active        : out   std_logic_vector(31 downto 0);
        Ev_IntReqDiscarded : out   std_logic;
        Ev_AckReqDiscarded : out   std_logic;
        Ev_AckIgnored      : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_ni_int is

    constant TimerMax_c : natural := 2**TimerWidth_g;

    type Timers_t is array (0 to 31) of natural range 0 to TimerMax_c;

    type TwoProcess_r is record
        TickCnt   : unsigned(15 downto 0);
        Active    : std_logic_vector(31 downto 0);
        IntPend   : std_logic_vector(31 downto 0);
        AckPend   : std_logic_vector(31 downto 0);
        Holdoff   : Timers_t;
        Delay     : Timers_t;
        IndInt    : std_logic;
        IndIntIid : std_logic_vector(4 downto 0);
        IndAck    : std_logic;
        IndAckIid : std_logic_vector(4 downto 0);
        IntDisc   : std_logic;
        AckDisc   : std_logic;
        AckIgn    : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal AckElig  : std_logic_vector(31 downto 0);
    signal IntGrant : std_logic_vector(31 downto 0);
    signal AckGrant : std_logic_vector(31 downto 0);
    signal IntIid   : std_logic_vector(4 downto 0);
    signal AckIid   : std_logic_vector(4 downto 0);

    -- Index of the set bit of a one-hot vector
    function oneHotIndex (vec : std_logic_vector(31 downto 0)) return std_logic_vector is
        variable Idx_v : std_logic_vector(4 downto 0) := (others => '0');
    begin

        for i in 0 to 31 loop
            if vec(i) = '1' then
                Idx_v := Idx_v or std_logic_vector(to_unsigned(i, 5));
            end if;
        end loop;

        return Idx_v;
    end function;

    -- Counter value for an interval of at least n ticks: n + 1 (the first tick may come at once)
    function loadValue (n : std_logic_vector) return natural is
    begin
        if unsigned(n) = 0 then
            return 0;
        else
            return to_integer(unsigned(n)) + 1;
        end if;
    end function;

begin

    -- Acknowledgement codes are eligible after their delay
    g_elig : for i in 0 to 31 generate
        AckElig(i) <= r.AckPend(i) when r.Delay(i) = 0 else '0';
    end generate;

    -- Waiting codes: the highest identifier first
    i_arb_int : entity olo.olo_base_arb_prio
        generic map (
            Width_g   => 32,
            Latency_g => 0
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Req    => r.IntPend,
            Out_Grant => IntGrant
        );

    i_arb_ack : entity olo.olo_base_arb_prio
        generic map (
            Width_g   => 32,
            Latency_g => 0
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Req    => AckElig,
            Out_Grant => AckGrant
        );

    IntIid <= oneHotIndex(IntGrant);
    AckIid <= oneHotIndex(AckGrant);

    p_comb : process (all) is
        variable v      : TwoProcess_r;
        variable Tick_v : boolean;
        variable Idx_v  : natural range 0 to 31;
    begin
        v         := r;
        v.IndInt  := '0';
        v.IndAck  := '0';
        v.IntDisc := '0';
        v.AckDisc := '0';
        v.AckIgn  := '0';

        -- Tick of the timers
        Tick_v := r.TickCnt = 0;
        if Tick_v then
            if unsigned(Cfg_Tick) = 0 then
                v.TickCnt := (others => '0');
            else
                v.TickCnt := unsigned(Cfg_Tick) - 1;
            end if;
        else
            v.TickCnt := r.TickCnt - 1;
        end if;

        for i in 0 to 31 loop
            if Tick_v and r.Holdoff(i) /= 0 then
                v.Holdoff(i) := r.Holdoff(i) - 1;
            end if;
            if Tick_v and r.Delay(i) /= 0 then
                v.Delay(i) := r.Delay(i) - 1;
            end if;
        end loop;

        -- Codes taken by the Data Link layer; the minimum interval starts when an interrupt code is sent
        if TxInt_Grant = '1' then
            Idx_v            := to_integer(unsigned(IntIid));
            v.IntPend(Idx_v) := '0';
            if Tx_Discarded = '0' then
                v.Holdoff(Idx_v) := loadValue(Cfg_Holdoff);
            end if;
        end if;
        if TxAck_Grant = '1' then
            v.AckPend(to_integer(unsigned(AckIid))) := '0';
        end if;

        -- DISTRIBUTED_INTERRUPT.request (ECSS 5.6.5.4b, c, d)
        if IntReq_Valid = '1' then
            Idx_v := to_integer(unsigned(IntReq_Iid));
            if r.Holdoff(Idx_v) /= 0 or r.IntPend(Idx_v) = '1' then
                v.IntDisc := '1';
            else
                v.IntPend(Idx_v) := '1';
            end if;
        end if;

        -- DISTRIBUTED_INTERRUPT_ACK.request (ECSS 6.1.3.4.4, 5.6.5.6c, d)
        if AckReq_Valid = '1' then
            Idx_v           := to_integer(unsigned(AckReq_Iid));
            v.Active(Idx_v) := '0';
            if Cfg_AckMode = '1' then
                v.AckPend(Idx_v) := '1';
            else
                v.AckDisc := '1';
            end if;
        end if;

        -- Received interrupt code (ECSS 5.6.5.4e): interrupt register and minimum acknowledgement delay
        if RxInt_Valid = '1' then
            Idx_v           := to_integer(unsigned(RxInt_Iid));
            v.Active(Idx_v) := '1';
            v.Delay(Idx_v)  := loadValue(Cfg_AckDelay);
            v.IndInt        := '1';
            v.IndIntIid     := RxInt_Iid;
        end if;

        -- Received acknowledgement code (ECSS 5.6.5.6g, h)
        if RxAck_Valid = '1' then
            if Cfg_AckMode = '1' then
                v.IndAck    := '1';
                v.IndAckIid := RxAck_Iid;
            else
                v.AckIgn := '1';
            end if;
        end if;

        if Cfg_PortReset = '1' then
            v.Active  := (others => '0');
            v.IntPend := (others => '0');
            v.AckPend := (others => '0');
            v.Holdoff := (others => 0);
            v.Delay   := (others => 0);
        end if;

        r_next <= v;
    end process;

    TxInt_Iid          <= IntIid;
    TxInt_Valid        <= '1' when r.IntPend /= x"00000000" else '0';
    TxAck_Iid          <= AckIid;
    TxAck_Valid        <= '1' when AckElig /= x"00000000" else '0';
    IndInt_Iid         <= r.IndIntIid;
    IndInt_Valid       <= r.IndInt;
    IndAck_Iid         <= r.IndAckIid;
    IndAck_Valid       <= r.IndAck;
    Stat_Active        <= r.Active;
    Ev_IntReqDiscarded <= r.IntDisc;
    Ev_AckReqDiscarded <= r.AckDisc;
    Ev_AckIgnored      <= r.AckIgn;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.TickCnt <= (others => '0');
                r.Active  <= (others => '0');
                r.IntPend <= (others => '0');
                r.AckPend <= (others => '0');
                r.Holdoff <= (others => 0);
                r.Delay   <= (others => 0);
                r.IndInt  <= '0';
                r.IndAck  <= '0';
                r.IntDisc <= '0';
                r.AckDisc <= '0';
                r.AckIgn  <= '0';
            end if;
        end if;
    end process;

end architecture;
