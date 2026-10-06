---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Data-Strobe model of a SpaceWire far end. The transmitter sends the characters queued in
-- owr_tb_ds_pkg.FarEnd_v (instance Index_g) with the configured bit period, Nulls or no transition
-- when the queue is empty, and injects simultaneous transitions. The receiver decodes the data and
-- strobe signals of the port in continuous time and logs every character and every edge.
--
-- What this model does NOT check or reproduce:
-- - It has no link state machine and no flow control: the test sequencer decides what is sent.
-- - It does not report errors of the decoded stream as alerts; parity and ESC errors are counted
--   (FarEnd_v.rxErrors) and the decoder searches for the next Null. After a time without an edge
--   (FarEnd_v.setRxTimeout, default 2 us) the decoder also searches for the next Null (transmitter of
--   the port reset).
-- - Line effects (skew, jitter, attenuation) are not modelled; the bit period is exact.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.owr_tb_ds_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_tb_ds_bfm is
    generic (
        Index_g : natural := 0
    );
    port (
        -- Lines driven by the model (to the receiver of the port)
        DOut : out   std_logic := '0';
        SOut : out   std_logic := '0';
        -- Lines received by the model (from the transmitter of the port)
        DIn  : in    std_logic;
        SIn  : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_tb_ds_bfm is

begin

    -----------------------------------------------------------------------------------------------
    -- Transmitter
    -----------------------------------------------------------------------------------------------
    p_tx : process is
        variable Acc_v    : std_logic := '0';
        variable D_v      : std_logic := '0';
        variable S_v      : std_logic := '0';
        variable Char_v   : TbChar_t;
        variable Enc_v    : TbBits_t;
        variable Mode_v   : TbTxMode_t;
        variable Period_v : time;
    begin
        DOut <= '0';
        SOut <= '0';

        loop
            Mode_v   := FarEnd_v.getMode(Index_g);
            Period_v := FarEnd_v.getBitPeriod(Index_g);
            if Mode_v = TbModeOff then
                -- Controlled reset: strobe first, data one bit period later
                if S_v = '1' then
                    S_v  := '0';
                    SOut <= '0';
                    FarEnd_v.setTxEdge(Index_g);
                    wait for Period_v;
                end if;
                if D_v = '1' then
                    D_v  := '0';
                    DOut <= '0';
                    FarEnd_v.setTxEdge(Index_g);
                    wait for Period_v;
                end if;
                Acc_v := '0';
                wait for 10 ns;
            elsif FarEnd_v.txCount(Index_g) > 0 or Mode_v = TbModeNull then
                if FarEnd_v.txCount(Index_g) > 0 then
                    Char_v := FarEnd_v.txPop(Index_g);
                else
                    Char_v := tbChar(TbNull);
                end if;
                FarEnd_v.countSent(Index_g, Char_v.Kind);
                Enc_v := tbEncode(Char_v, Acc_v);

                for i in 0 to Enc_v.Len - 1 loop
                    if FarEnd_v.takeSimultaneous(Index_g) then
                        D_v := not D_v;
                        S_v := not S_v;
                    elsif Enc_v.Bits(i) = D_v then
                        S_v := not S_v;
                    else
                        D_v := Enc_v.Bits(i);
                    end if;
                    DOut <= D_v;
                    SOut <= S_v;
                    FarEnd_v.setTxEdge(Index_g);
                    wait for Period_v;
                end loop;

                Acc_v := Enc_v.Acc;
            else
                wait for Period_v;
            end if;
        end loop;

    end process;

    -----------------------------------------------------------------------------------------------
    -- Receiver
    -----------------------------------------------------------------------------------------------
    p_rx : process is
        constant Pattern_c : std_logic_vector(8 downto 0) := "011101000"; -- bit 8 received first
        type     TimeHist_t is array (0 to 8) of time;

        variable PrevD_v  : std_logic := 'U';
        variable PrevS_v  : std_logic := 'U';
        variable Init_v   : boolean   := false;
        variable Bit_v    : std_logic;
        variable Win_v    : std_logic_vector(8 downto 0);
        variable Hist_v   : TimeHist_t;
        variable Synced_v : boolean;
        variable Phase_v  : natural range 0 to 2; -- 0 parity, 1 data-control flag, 2 data bits
        variable Par_v    : std_logic;
        variable Ctl_v    : std_logic;
        variable Acc_v    : std_logic;
        variable Cnt_v    : natural range 0 to 8;
        variable Len_v    : natural range 0 to 8;
        variable Data_v   : std_logic_vector(7 downto 0);
        variable CharT_v  : time;
        variable Esc_v    : boolean;
        variable EscT_v   : time;
        variable Typ_v    : std_logic_vector(1 downto 0);
        variable Char_v   : TbChar_t;

        procedure resync is
        begin
            Synced_v := false;
            Win_v    := (others => '1');
            Esc_v    := false;
        end procedure;

        procedure logChar (
            kind : TbCharKind_t;
            data : std_logic_vector(7 downto 0);
            t    : time) is
        begin
            Char_v      := TbCharInit_c;
            Char_v.Kind := kind;
            Char_v.Data := data;
            Char_v.T    := t;
            FarEnd_v.rxPush(Index_g, Char_v);
        end procedure;

        procedure decodeError is
        begin
            FarEnd_v.rxError(Index_g);
            resync;
        end procedure;

    -- Comment for the style checker: procedures above, statements below
    begin
        resync;
        wait for 0 ns;
        if (DIn = '0' or DIn = '1') and (SIn = '0' or SIn = '1') then
            Init_v  := true;
            PrevD_v := DIn;
            PrevS_v := SIn;
        end if;

        loop
            wait on DIn, SIn for FarEnd_v.getRxTimeout(Index_g);
            if DIn = PrevD_v and SIn = PrevS_v then
                -- No edge for the timeout: transmitter of the port stopped
                resync;
                next;
            end if;
            if not Init_v then
                -- Ignore the initialisation of the signals ('U' to '0')
                if (DIn = '0' or DIn = '1') and (SIn = '0' or SIn = '1') then
                    Init_v := true;
                end if;
                PrevD_v := DIn;
                PrevS_v := SIn;
                next;
            end if;
            FarEnd_v.edgePush(Index_g, (T => now, D => DIn, S => SIn));
            if DIn /= PrevD_v and SIn /= PrevS_v then
                -- Simultaneous transition: not a bit, the stream is lost
                PrevD_v := DIn;
                PrevS_v := SIn;
                decodeError;
                next;
            end if;
            PrevD_v := DIn;
            PrevS_v := SIn;
            Bit_v   := DIn;

            if not Synced_v then
                -- Null detection (ECSS 5.4.6): 0111 0100 0 with the parity bit of the next character
                Win_v          := Win_v(7 downto 0) & Bit_v;
                Hist_v(0 to 7) := Hist_v(1 to 8);
                Hist_v(8)      := now;
                if Win_v = Pattern_c then
                    Synced_v := true;
                    logChar(TbNull, x"00", Hist_v(0));
                    Par_v    := Bit_v;
                    CharT_v  := now;
                    Acc_v    := '0';
                    Phase_v  := 1;
                end if;
            else

                case Phase_v is

                    when 0 =>
                        Par_v   := Bit_v;
                        CharT_v := now;
                        Phase_v := 1;

                    when 1 =>
                        Ctl_v := Bit_v;
                        if (Par_v xor Ctl_v xor Acc_v) /= '1' then
                            decodeError;
                        else
                            if Ctl_v = '1' then
                                Len_v := 2;
                            else
                                Len_v := 8;
                            end if;
                            Cnt_v   := 0;
                            Data_v  := (others => '0');
                            Phase_v := 2;
                        end if;

                    when 2 =>
                        Data_v(Cnt_v) := Bit_v;
                        Cnt_v         := Cnt_v + 1;
                        if Cnt_v = Len_v then
                            Phase_v := 0;
                            if Ctl_v = '0' then
                                Acc_v := '0';

                                for i in 0 to 7 loop
                                    Acc_v := Acc_v xor Data_v(i);
                                end loop;

                                if Esc_v then
                                    Esc_v := false;
                                    logChar(TbBc, Data_v, EscT_v);
                                else
                                    logChar(TbData, Data_v, CharT_v);
                                end if;
                            else
                                Typ_v := Data_v(1 downto 0);
                                Acc_v := Typ_v(0) xor Typ_v(1);
                                if Esc_v then
                                    Esc_v := false;
                                    if Typ_v = "00" then
                                        logChar(TbNull, x"00", EscT_v);
                                    else
                                        -- ESC error (ECSS 5.4.9)
                                        decodeError;
                                    end if;
                                elsif Typ_v = "11" then
                                    Esc_v  := true;
                                    EscT_v := CharT_v;
                                elsif Typ_v = "00" then
                                    logChar(TbFct, x"00", CharT_v);
                                elsif Typ_v = "10" then
                                    logChar(TbEop, x"00", CharT_v);
                                else
                                    logChar(TbEep, x"00", CharT_v);
                                end if;
                            end if;
                        end if;

                end case;

            end if;
        end loop;

    end process;

end architecture;
