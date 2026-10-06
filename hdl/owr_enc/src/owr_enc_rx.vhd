---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- SpaceWire receiver (EN-2): samples the Data-Strobe signals with the clock, recovers the bits,
-- detects the first Null, decodes characters and control codes and detects parity errors, ESC
-- errors and disconnects (ECSS-E-ST-50-12C Rev.1 clauses 5.4.2 to 5.4.9). A character is passed
-- only after the parity bit of the next character has been checked.
--
-- Documentation: hdl/owr_enc/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.owr_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_enc_rx is
    generic (
        DisconnectCycles_g : positive              := 83;
        SyncStages_g       : positive range 2 to 4 := 2
    );
    port (
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        -- Control from the link state machine
        RxEnable      : in    std_logic;
        -- Data and strobe (asynchronous)
        Spw_DIn       : in    std_logic;
        Spw_SIn       : in    std_logic;
        -- Received characters and control codes (one-cycle events)
        Char_Valid    : out   std_logic;
        Char_Kind     : out   CharKind_t;
        Char_Data     : out   std_logic_vector(7 downto 0);
        -- Status
        Rx_GotNull    : out   std_logic;
        Rx_ParityErr  : out   std_logic;
        Rx_EscErr     : out   std_logic;
        Rx_Disconnect : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of owr_enc_rx is

    -- Bit 8 is received first: ESC (0 1 1 1), FCT (0 1 0 0), parity bit of the next character (0)
    constant NullPattern_c : std_logic_vector(8 downto 0) := "011101000";

    type Phase_t is (Parity_s, Flag_s, Bits_s);

    -- Character waiting for the parity check of the next character
    type Pending_t is (None_s, Data_s, Fct_s, Eop_s, Eep_s, Esc_s);

    type TwoProcess_r is record
        PrevD     : std_logic;
        PrevS     : std_logic;
        FirstEdge : std_logic;
        TimeCnt   : natural range 0 to DisconnectCycles_g;
        GotNull   : std_logic;
        Halted    : std_logic;
        Window    : std_logic_vector(8 downto 0);
        Phase     : Phase_t;
        Par       : std_logic;
        Flag      : std_logic;
        BitCnt    : natural range 0 to 7;
        Bits      : std_logic_vector(7 downto 0);
        Acc       : std_logic;
        PrevAcc   : std_logic;
        Pending   : Pending_t;
        PendData  : std_logic_vector(7 downto 0);
        EscSeen   : std_logic;
        OutValid  : std_logic;
        OutKind   : CharKind_t;
        OutData   : std_logic_vector(7 downto 0);
        ParErr    : std_logic;
        EscErr    : std_logic;
        Disc      : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal DSync : std_logic;
    signal SSync : std_logic;

begin

    -- Synchroniser of the asynchronous inputs
    b_sync : block is
        signal Async : std_logic_vector(1 downto 0);
        signal Sync  : std_logic_vector(1 downto 0);
    begin
        Async <= Spw_SIn & Spw_DIn;

        i_sync : entity olo.olo_intf_sync
            generic map (
                Width_g      => 2,
                SyncStages_g => SyncStages_g
            )
            port map (
                Clk       => Clk,
                Rst       => Rst,
                DataAsync => Async,
                DataSync  => Sync
            );

        DSync <= Sync(0);
        SSync <= Sync(1);
    end block;

    p_comb : process (all) is
        variable v        : TwoProcess_r;
        variable Edge_v   : boolean;
        variable BitVld_v : boolean;
        variable Kind_v   : Pending_t;
        variable Typ_v    : CtrlType_t;

        -- Releases the pending character after its parity has been checked (reads the copy of the registers in v,
        -- which this cycle has not changed before the call)
        procedure releasePending is
        begin
            if v.Pending = Esc_s then
                if v.EscSeen = '1' then
                    -- ECSS 5.4.9: ESC followed by ESC
                    v.EscErr := '1';
                    v.Halted := '1';
                else
                    v.EscSeen := '1';
                end if;
            elsif v.Pending /= None_s then
                v.OutValid := '1';
                v.OutData  := v.PendData;
                if v.EscSeen = '1' then
                    v.EscSeen := '0';
                    if v.Pending = Fct_s then
                        v.OutKind := KindNull_c;
                    elsif v.Pending = Data_s then
                        v.OutKind := KindBc_c;
                    else
                        -- ECSS 5.4.9: ESC followed by EOP or EEP
                        v.OutValid := '0';
                        v.EscErr   := '1';
                        v.Halted   := '1';
                    end if;
                else

                    case v.Pending is

                        when Fct_s =>
                            v.OutKind := KindFct_c;

                        when Eop_s =>
                            v.OutKind := KindEop_c;

                        when Eep_s =>
                            v.OutKind := KindEep_c;

                        when others =>
                            v.OutKind := KindData_c;

                    end case;

                end if;
            end if;
            v.Pending := None_s;
        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        v := r;

        -- Events last one cycle
        v.OutValid := '0';
        v.ParErr   := '0';
        v.EscErr   := '0';
        v.Disc     := '0';

        -- Bit recovery (ECSS 5.4.4): a bit on every change of data XOR strobe
        Edge_v   := DSync /= r.PrevD or SSync /= r.PrevS;
        BitVld_v := (DSync xor SSync) /= (r.PrevD xor r.PrevS);
        v.PrevD  := DSync;
        v.PrevS  := SSync;

        if RxEnable = '0' then
            -- Receiver reset (ECSS 5.4.2e.2); gotNull is cleared only here (ECSS 5.4.6b)
            v.FirstEdge := '0';
            v.TimeCnt   := 0;
            v.GotNull   := '0';
            v.Halted    := '0';
            v.Window    := (others => '1');
            v.Pending   := None_s;
            v.EscSeen   := '0';
        elsif r.Halted = '0' then

            -- Disconnect (ECSS 5.4.8): enabled by the first edge after the receiver is enabled
            if Edge_v then
                v.FirstEdge := '1';
                v.TimeCnt   := 0;
            elsif r.FirstEdge = '1' then
                if r.TimeCnt = DisconnectCycles_g - 1 then
                    v.Disc   := '1';
                    v.Halted := '1';
                else
                    v.TimeCnt := r.TimeCnt + 1;
                end if;
            end if;

            if BitVld_v and v.Halted = '0' then
                if r.GotNull = '0' then
                    -- Null detection (ECSS 5.4.6)
                    v.Window := r.Window(7 downto 0) & DSync;
                    if v.Window = NullPattern_c then
                        v.GotNull := '1';
                        v.Par     := DSync;
                        v.PrevAcc := '0';
                        v.Phase   := Flag_s;
                        v.Pending := None_s;
                        v.EscSeen := '0';
                    end if;
                else

                    case r.Phase is

                        when Parity_s =>
                            v.Par   := DSync;
                            v.Phase := Flag_s;

                        when Flag_s =>
                            v.Flag := DSync;
                            if (r.Par xor DSync xor r.PrevAcc) /= '1' then
                                -- Parity error (ECSS 5.4.7): the pending character is not passed
                                v.ParErr  := '1';
                                v.Halted  := '1';
                                v.Pending := None_s;
                            else
                                releasePending;
                                v.BitCnt := 0;
                                v.Acc    := '0';
                                v.Bits   := (others => '0');
                                v.Phase  := Bits_s;
                            end if;

                        when Bits_s =>
                            v.Bits(r.BitCnt) := DSync;
                            v.Acc            := r.Acc xor DSync;
                            if (r.Flag = '1' and r.BitCnt = 1) or r.BitCnt = 7 then
                                -- Character complete: pending until the next parity check
                                v.PrevAcc  := v.Acc;
                                v.PendData := v.Bits;
                                v.Phase    := Parity_s;
                                if r.Flag = '0' then
                                    Kind_v := Data_s;
                                else
                                    Typ_v := v.Bits(1 downto 0);
                                    if Typ_v = CtrlFct_c then
                                        Kind_v := Fct_s;
                                    elsif Typ_v = CtrlEop_c then
                                        Kind_v := Eop_s;
                                    elsif Typ_v = CtrlEep_c then
                                        Kind_v := Eep_s;
                                    else
                                        Kind_v := Esc_s;
                                    end if;
                                end if;
                                v.Pending := Kind_v;
                            else
                                v.BitCnt := r.BitCnt + 1;
                            end if;

                        -- Recovery state for an illegal state
                        -- coverage off
                        when others =>
                            v.Phase := Parity_s;
                        -- coverage on

                    end case;

                end if;
            end if;
        end if;

        r_next <= v;
    end process;

    Char_Valid    <= r.OutValid;
    Char_Kind     <= r.OutKind;
    Char_Data     <= r.OutData;
    Rx_GotNull    <= r.GotNull;
    Rx_ParityErr  <= r.ParErr;
    Rx_EscErr     <= r.EscErr;
    Rx_Disconnect <= r.Disc;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.PrevD     <= '0';
                r.PrevS     <= '0';
                r.FirstEdge <= '0';
                r.TimeCnt   <= 0;
                r.GotNull   <= '0';
                r.Halted    <= '0';
                r.Window    <= (others => '1');
                r.Phase     <= Parity_s;
                r.Pending   <= None_s;
                r.EscSeen   <= '0';
                r.OutValid  <= '0';
                r.ParErr    <= '0';
                r.EscErr    <= '0';
                r.Disc      <= '0';
            end if;
        end if;
    end process;

end architecture;
