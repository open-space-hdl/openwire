---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Transmit scheduler (DL-5) of the SpaceWire Data Link layer: presents the next character by
-- state and sending priority (broadcast code, FCT, N-Char, Null), keeps one broadcast code slot,
-- discards broadcast codes outside Run and the remainder of a packet during link error recovery
-- (ECSS-E-ST-50-12C Rev.1 clauses 5.5.6, 5.5.8.4a.1 and 5.5.9).
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
entity owr_dl_tx is
    port (
        Clk              : in    std_logic;
        Rst              : in    std_logic;
        -- Link state, port reset
        State            : in    LinkState_t;
        Cfg_PortReset    : in    std_logic;
        -- Flow control manager
        Fc_FctRequest    : in    std_logic;
        Fc_TxCreditAvail : in    std_logic;
        -- Transmit FIFO (first word fall through)
        TxFifo_Data      : in    NChar_t;
        TxFifo_Ded       : in    std_logic;
        TxFifo_Valid     : in    std_logic;
        TxFifo_Ready     : out   std_logic;
        -- Broadcast codes of the Network layer
        TxBc_Data        : in    std_logic_vector(7 downto 0);
        TxBc_Valid       : in    std_logic;
        TxBc_Ready       : out   std_logic;
        TxBc_Discarded   : out   std_logic;
        -- Link error recovery
        Rec_Start        : in    std_logic;
        Rec_Busy         : out   std_logic;
        -- Encoding layer
        TxChar_Kind      : out   CharKind_t;
        TxChar_Data      : out   std_logic_vector(7 downto 0);
        TxChar_Ack       : in    std_logic;
        -- Sent characters
        SentNull         : out   std_logic;
        SentFct          : out   std_logic;
        SentNChar        : out   std_logic;
        -- Status
        Stat_Spill       : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_dl_tx is

    type TwoProcess_r is record
        BcValid  : std_logic;
        BcData   : std_logic_vector(7 downto 0);
        Spill    : std_logic;
        RecSpill : std_logic;
        InPacket : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Run_v   : boolean;
        variable NChar_v : boolean;
        variable Kind_v  : CharKind_t;
        variable Data_v  : std_logic_vector(7 downto 0);
        variable Pop_v   : std_logic;
    begin
        v              := r;
        Pop_v          := '0';
        SentNull       <= '0';
        SentFct        <= '0';
        SentNChar      <= '0';
        TxBc_Discarded <= '0';

        Run_v := State = StateRun_c;

        -- Broadcast code slot (ECSS 5.5.9): accepted in Run, discarded outside Run
        TxBc_Ready <= not r.BcValid;
        if TxBc_Valid = '1' and r.BcValid = '0' then
            if Run_v then
                v.BcValid := '1';
                v.BcData  := TxBc_Data;
            else
                TxBc_Discarded <= '1';
            end if;
        end if;

        -- N-Char available for sending (ECSS 5.5.6d)
        NChar_v := Run_v and TxFifo_Valid = '1' and Fc_TxCreditAvail = '1' and r.Spill = '0';

        -- Presented character by state and priority (ECSS 5.5.6a)
        Kind_v := KindNull_c;
        Data_v := TxFifo_Data(7 downto 0);
        if State = StateConnecting_c then
            if Fc_FctRequest = '1' then
                Kind_v := KindFct_c;
            end if;
        elsif Run_v then
            if r.BcValid = '1' then
                Kind_v := KindBc_c;
                Data_v := r.BcData;
            elsif Fc_FctRequest = '1' then
                Kind_v := KindFct_c;
            elsif NChar_v then
                if TxFifo_Ded = '1' then
                    -- Double error: the corrupted N-Char is replaced by an EEP
                    Kind_v := KindEep_c;
                elsif TxFifo_Data(NCharFlagIdx_c) = '0' then
                    Kind_v := KindData_c;
                elsif TxFifo_Data(0) = '0' then
                    Kind_v := KindEop_c;
                else
                    Kind_v := KindEep_c;
                end if;
            end if;
        end if;
        TxChar_Kind <= Kind_v;
        TxChar_Data <= Data_v;

        -- Character taken by the transmitter
        if TxChar_Ack = '1' then
            if Kind_v = KindBc_c then
                v.BcValid := '0';
            elsif Kind_v = KindFct_c then
                SentFct <= '1';
            elsif Kind_v = KindNull_c then
                SentNull <= '1';
            else
                SentNChar <= '1';
                Pop_v     := '1';
                if TxFifo_Ded = '1' then
                    v.Spill    := '1';
                    v.InPacket := '0';
                elsif Kind_v = KindData_c then
                    v.InPacket := '1';
                else
                    v.InPacket := '0';
                end if;
            end if;
        end if;

        -- Discard up to and including the next end of packet marker (ECSS 5.5.8.4a.1)
        if r.Spill = '1' and TxFifo_Valid = '1' then
            Pop_v := '1';
            if TxFifo_Data(NCharFlagIdx_c) = '1' and TxFifo_Ded = '0' then
                v.Spill    := '0';
                v.RecSpill := '0';
            end if;
        end if;

        -- Start of the link error recovery: discard the remainder of the packet being sent
        if Rec_Start = '1' and v.InPacket = '1' then
            v.Spill    := '1';
            v.RecSpill := '1';
            v.InPacket := '0';
        end if;

        -- A waiting broadcast code is discarded in ErrorReset (ECSS 5.5.7.2b)
        if State = StateErrorReset_c then
            v.BcValid := '0';
        end if;

        if Cfg_PortReset = '1' then
            v.BcValid  := '0';
            v.Spill    := '0';
            v.RecSpill := '0';
            v.InPacket := '0';
        end if;

        TxFifo_Ready <= Pop_v;
        r_next       <= v;
    end process;

    Rec_Busy   <= r.RecSpill;
    Stat_Spill <= r.Spill;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.BcValid  <= '0';
                r.Spill    <= '0';
                r.RecSpill <= '0';
                r.InPacket <= '0';
            end if;
        end if;
    end process;

end architecture;
