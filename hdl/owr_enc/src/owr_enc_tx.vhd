---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- SpaceWire transmitter (EN-1): encodes characters and control codes with odd parity, serialises
-- them and drives the Data-Strobe signals with the initial or the run bit period
-- (ECSS-E-ST-50-12C Rev.1 clauses 5.4.2 to 5.4.5 and 5.4.10).
--
-- Documentation: hdl/owr_enc/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.owr_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_enc_tx is
    generic (
        InitDiv_g : positive range 1 to 256 := 10
    );
    port (
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        -- Control from the link state machine
        TxEnable     : in    std_logic;
        TxRun        : in    std_logic;
        Cfg_RunDiv   : in    std_logic_vector(7 downto 0);
        -- Character to send, taken with Char_Ack
        Char_Kind    : in    CharKind_t;
        Char_Data    : in    std_logic_vector(7 downto 0);
        Char_Ack     : out   std_logic;
        -- Data and strobe
        Spw_DOut     : out   std_logic;
        Spw_SOut     : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_enc_tx is

    type TwoProcess_r is record
        D      : std_logic;
        S      : std_logic;
        Active : std_logic;
        First  : std_logic;
        Bits   : std_logic_vector(13 downto 0);
        Remain : natural range 0 to 14;
        Acc    : std_logic;
        DivCnt : natural range 0 to 255;
    end record;

    signal r, r_next : TwoProcess_r;

    -- Bits of a character, bit 0 is sent first
    type Encoded_t is record
        Bits : std_logic_vector(13 downto 0);
        Len  : natural range 4 to 14;
        Acc  : std_logic;
    end record;

    function encode (
        kind : CharKind_t;
        data : std_logic_vector(7 downto 0);
        acc  : std_logic) return Encoded_t is
        variable Res_v : Encoded_t;
        variable Typ_v : CtrlType_t;
    begin
        Res_v.Bits := (others => '0');
        if kind = KindData_c then
            -- ECSS 5.4.3.1: P 0 D0 .. D7
            Res_v.Bits(0)          := parityBit(acc, '0');
            Res_v.Bits(1)          := '0';
            Res_v.Bits(9 downto 2) := data;
            Res_v.Len              := 10;
            Res_v.Acc              := xorReduce(data);
        elsif kind = KindNull_c or kind = KindBc_c then
            -- ECSS 5.4.3.3: ESC (P 1 1 1) followed by FCT (P 1 0 0) or a data character
            Res_v.Bits(0)          := parityBit(acc, '1');
            Res_v.Bits(3 downto 1) := "111";
            if kind = KindNull_c then
                Res_v.Bits(4)          := parityBit('0', '1');
                Res_v.Bits(7 downto 5) := "001";
                Res_v.Len              := 8;
                Res_v.Acc              := '0';
            else
                Res_v.Bits(4)           := parityBit('0', '0');
                Res_v.Bits(5)           := '0';
                Res_v.Bits(13 downto 6) := data;
                Res_v.Len               := 14;
                Res_v.Acc               := xorReduce(data);
            end if;
        else
            -- ECSS 5.4.3.2: P 1 T0 T1
            if kind = KindEop_c then
                Typ_v := CtrlEop_c;
            elsif kind = KindEep_c then
                Typ_v := CtrlEep_c;
            else
                Typ_v := CtrlFct_c;
            end if;
            Res_v.Bits(0)          := parityBit(acc, '1');
            Res_v.Bits(1)          := '1';
            Res_v.Bits(3 downto 2) := Typ_v;
            Res_v.Len              := 4;
            Res_v.Acc              := Typ_v(0) xor Typ_v(1);
        end if;
        return Res_v;
    end function;

begin

    p_comb : process (all) is
        variable v     : TwoProcess_r;
        variable Enc_v : Encoded_t;
        variable Div_v : natural range 1 to 256;
        variable Bit_v : std_logic;
    begin
        v        := r;
        Char_Ack <= '0';

        -- Bit period of the next bit (ECSS 5.4.10)
        if TxRun = '1' then
            Div_v := maximum(1, to_integer(unsigned(Cfg_RunDiv)));
        else
            Div_v := InitDiv_g;
        end if;

        if TxEnable = '1' then
            if r.Active = '0' then
                -- Start after the reset of data and strobe: the first character is taken at once
                if r.D = '0' and r.S = '0' then
                    v.Active := '1';
                    v.First  := '1';
                    v.Acc    := '0';
                    v.Remain := 0;
                    v.DivCnt := 0;
                end if;
            elsif r.DivCnt = 0 then
                -- Bit boundary
                v.DivCnt := Div_v - 1;
                if r.Remain = 0 then
                    if r.First = '1' then
                        -- ECSS 5.4.5: the first character is a Null; the presented character is taken only if
                        -- it is a Null
                        Enc_v    := encode(KindNull_c, Char_Data, '0');
                        Char_Ack <= '1' when Char_Kind = KindNull_c else '0';
                        v.First  := '0';
                    else
                        Enc_v    := encode(Char_Kind, Char_Data, r.Acc);
                        Char_Ack <= '1';
                    end if;
                    v.Bits   := Enc_v.Bits;
                    v.Remain := Enc_v.Len;
                    v.Acc    := Enc_v.Acc;
                end if;
                -- Data-Strobe encoding (ECSS 5.4.4a)
                Bit_v := v.Bits(0);
                if Bit_v = r.D then
                    v.S := not r.S;
                else
                    v.D := Bit_v;
                end if;
                v.Bits   := '0' & v.Bits(13 downto 1);
                v.Remain := v.Remain - 1;
            else
                v.DivCnt := r.DivCnt - 1;
            end if;
        else
            -- Controlled reset (ECSS 5.4.4c to e): strobe first, data one bit period later
            v.Active := '0';
            v.Remain := 0;
            if r.DivCnt = 0 then
                v.DivCnt := Div_v - 1;
                if r.S = '1' then
                    v.S := '0';
                elsif r.D = '1' then
                    v.D := '0';
                end if;
            else
                v.DivCnt := r.DivCnt - 1;
            end if;
        end if;

        r_next <= v;
    end process;

    Spw_DOut <= r.D;
    Spw_SOut <= r.S;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.D      <= '0';
                r.S      <= '0';
                r.Active <= '0';
                r.First  <= '0';
                r.Remain <= 0;
                r.Acc    <= '0';
                r.DivCnt <= 0;
            end if;
        end if;
    end process;

end architecture;
