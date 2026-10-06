---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Receive handler (DL-6) of the SpaceWire Data Link layer: writes received N-Chars to the receive
-- FIFO and passes received broadcast codes in the Run state, and writes an EEP after a link error
-- in the middle of a packet (ECSS-E-ST-50-12C Rev.1 clauses 5.5.2 and 5.5.8.4a.2 to a.4).
--
-- Documentation: hdl/owr_dl/docs/architecture.md

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
entity owr_dl_rx is
    port (
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        -- Link state, port reset
        State            : in    LinkState_t;
        Cfg_PortReset    : in    std_logic;
        -- Received characters of the Encoding layer
        RxChar_Valid     : in    std_logic;
        RxChar_Kind      : in    CharKind_t;
        RxChar_Data      : in    std_logic_vector(7 downto 0);
        -- Flow control manager
        Fc_RxCreditAvail : in    std_logic;
        -- Receive FIFO
        RxFifo_Data      : out   NChar_t;
        RxFifo_Valid     : out   std_logic;
        RxFifo_Ready     : in    std_logic;
        -- Broadcast codes to the Network layer
        RxBc_Data        : out   std_logic_vector(7 downto 0);
        RxBc_Valid       : out   std_logic;
        -- Link error recovery
        Rec_Start        : in    std_logic;
        Rec_Busy         : out   std_logic;
        EepPending       : out   std_logic;
        -- An N-Char arrived while the previous one was not yet written (never with correct credits)
        Ev_Overflow      : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_dl_rx is

    type TwoProcess_r is record
        WrValid  : std_logic;
        WrData   : NChar_t;
        InPacket : std_logic;
        EepPend  : std_logic;
        BcValid  : std_logic;
        BcData   : std_logic_vector(7 downto 0);
        Overflow : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable NChar_v : boolean;
        variable Word_v  : NChar_t;
    begin
        v          := r;
        v.BcValid  := '0';
        v.Overflow := '0';

        -- Write register accepted by the FIFO
        if r.WrValid = '1' and RxFifo_Ready = '1' then
            v.WrValid := '0';
        end if;

        NChar_v := RxChar_Valid = '1' and (RxChar_Kind = KindData_c or RxChar_Kind = KindEop_c or
                                           RxChar_Kind = KindEep_c);

        if State = StateRun_c and RxChar_Valid = '1' then
            -- Broadcast codes to the Network layer (ECSS 5.5.7.7a.4)
            if RxChar_Kind = KindBc_c then
                v.BcValid := '1';
                v.BcData  := RxChar_Data;
            end if;
            -- N-Chars to the receive FIFO (ECSS 5.5.7.7a.3); not stored on a credit error (DL-4)
            if NChar_v and Fc_RxCreditAvail = '1' then
                if RxChar_Kind = KindData_c then
                    Word_v     := '0' & RxChar_Data;
                    v.InPacket := '1';
                elsif RxChar_Kind = KindEop_c then
                    Word_v     := NCharEop_c;
                    v.InPacket := '0';
                else
                    Word_v     := NCharEep_c;
                    v.InPacket := '0';
                end if;
                if v.WrValid = '1' then
                    v.Overflow := '1';
                else
                    v.WrValid := '1';
                    v.WrData  := Word_v;
                end if;
            end if;
        end if;

        -- Link error recovery (ECSS 5.5.8.4a.2 to a.4): EEP after a data character, written when there is room
        if Rec_Start = '1' and v.InPacket = '1' then
            v.EepPend  := '1';
            v.InPacket := '0';
        end if;
        if r.EepPend = '1' and v.WrValid = '0' then
            v.WrValid := '1';
            v.WrData  := NCharEep_c;
            v.EepPend := '0';
        end if;

        if Cfg_PortReset = '1' then
            v.WrValid  := '0';
            v.InPacket := '0';
            v.EepPend  := '0';
        end if;

        r_next <= v;
    end process;

    RxFifo_Data  <= r.WrData;
    RxFifo_Valid <= r.WrValid;
    RxBc_Data    <= r.BcData;
    RxBc_Valid   <= r.BcValid;
    Rec_Busy     <= r.EepPend or r.WrValid;
    EepPending   <= r.EepPend;
    Ev_Overflow  <= r.Overflow;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.WrValid  <= '0';
                r.InPacket <= '0';
                r.EepPend  <= '0';
                r.BcValid  <= '0';
                r.Overflow <= '0';
            end if;
        end if;
    end process;

end architecture;
