---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the Encoding layer: owr_enc at 100 MHz with the Data-Strobe far-end model
-- (instance 0). The characters of the transmitter come from the transmit queue of instance 1 of
-- owr_tb_ds_pkg.FarEnd_v (a Null when it is empty), the received characters are logged in the receive
-- log of instance 1.
--
-- Documentation: hdl/owr_enc/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.owr_pkg.all;
    use work.owr_tb_ds_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity owr_enc_th is
    port (
        Clk           : out   std_logic;
        Rst           : in    std_logic;
        TxEnable      : in    std_logic;
        RxEnable      : in    std_logic;
        TxRun         : in    std_logic;
        Cfg_RunDiv    : in    std_logic_vector(7 downto 0);
        Cfg_Loopback  : in    std_logic;
        Rx_GotNull    : out   std_logic;
        ParityErrCnt  : out   natural;
        EscErrCnt     : out   natural;
        DisconnectCnt : out   natural;
        DisconnectT   : out   time;
        TxAckCnt      : out   natural;
        Spw_DOut      : out   std_logic;
        Spw_SOut      : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of owr_enc_th is

    constant ClkPeriod_c : time := 10 ns;

    signal Clk_i     : std_logic := '0';
    signal TxKind    : CharKind_t;
    signal TxData    : std_logic_vector(7 downto 0);
    signal TxAck     : std_logic;
    signal RxValid   : std_logic;
    signal RxKind    : CharKind_t;
    signal RxData    : std_logic_vector(7 downto 0);
    signal ParityErr : std_logic;
    signal EscErr    : std_logic;
    signal DiscEvt   : std_logic;
    signal DOut      : std_logic;
    signal SOut      : std_logic;
    signal DIn       : std_logic;
    signal SIn       : std_logic;

    function toKind (kind : TbCharKind_t) return CharKind_t is
    begin

        case kind is

            when TbFct =>
                return KindFct_c;

            when TbData =>
                return KindData_c;

            when TbEop =>
                return KindEop_c;

            when TbEep =>
                return KindEep_c;

            when TbBc =>
                return KindBc_c;

            when others =>
                return KindNull_c;

        end case;

    end function;

    function toTbKind (kind : CharKind_t) return TbCharKind_t is
    begin
        if kind = KindFct_c then
            return TbFct;
        elsif kind = KindData_c then
            return TbData;
        elsif kind = KindEop_c then
            return TbEop;
        elsif kind = KindEep_c then
            return TbEep;
        elsif kind = KindBc_c then
            return TbBc;
        else
            return TbNull;
        end if;
    end function;

begin

    Clk_i <= not Clk_i after ClkPeriod_c / 2;
    Clk   <= Clk_i;

    i_dut : entity work.owr_enc
        generic map (
            ClkFreq_g => 100.0e6
        )
        port map (
            Clk           => Clk_i,
            Rst           => Rst,
            TxEnable      => TxEnable,
            RxEnable      => RxEnable,
            TxRun         => TxRun,
            Cfg_RunDiv    => Cfg_RunDiv,
            Cfg_Loopback  => Cfg_Loopback,
            TxChar_Kind   => TxKind,
            TxChar_Data   => TxData,
            TxChar_Ack    => TxAck,
            RxChar_Valid  => RxValid,
            RxChar_Kind   => RxKind,
            RxChar_Data   => RxData,
            Rx_GotNull    => Rx_GotNull,
            Rx_ParityErr  => ParityErr,
            Rx_EscErr     => EscErr,
            Rx_Disconnect => DiscEvt,
            Spw_DOut      => DOut,
            Spw_SOut      => SOut,
            Spw_DIn       => DIn,
            Spw_SIn       => SIn
        );

    Spw_DOut <= DOut;
    Spw_SOut <= SOut;

    i_far : entity work.owr_tb_ds_bfm
        generic map (
            Index_g => 0
        )
        port map (
            DOut => DIn,
            SOut => SIn,
            DIn  => DOut,
            SIn  => SOut
        );

    -- Character source of the transmitter: head of queue 1, popped when the transmitter takes it
    p_src : process (Clk_i) is
        variable Char_v   : TbChar_t;
        variable AckCnt_v : natural := 0;
    begin
        if rising_edge(Clk_i) then
            if TxAck = '1' then
                AckCnt_v := AckCnt_v + 1;
                if FarEnd_v.txCount(1) > 0 then
                    Char_v := FarEnd_v.txPop(1);
                end if;
            end if;
            TxAckCnt <= AckCnt_v;
        end if;
    end process;

    -- Presented character: evaluated every cycle from the queue head
    p_head : process is
        variable Char_v : TbChar_t;
    begin
        TxKind <= KindNull_c;
        TxData <= x"00";

        loop
            wait until falling_edge(Clk_i);
            if FarEnd_v.txCount(1) > 0 then
                Char_v := FarEnd_v.txPeek(1);
                TxKind <= toKind(Char_v.Kind);
                TxData <= Char_v.Data;
            else
                TxKind <= KindNull_c;
                TxData <= x"00";
            end if;
        end loop;

    end process;

    -- Logger of the receiver
    p_log : process (Clk_i) is
        variable Char_v    : TbChar_t;
        variable ParCnt_v  : natural := 0;
        variable EscCnt_v  : natural := 0;
        variable DiscCnt_v : natural := 0;
    begin
        if rising_edge(Clk_i) then
            if RxValid = '1' then
                Char_v      := TbCharInit_c;
                Char_v.Kind := toTbKind(RxKind);
                Char_v.Data := RxData;
                Char_v.T    := now;
                FarEnd_v.rxPush(1, Char_v);
            end if;
            if ParityErr = '1' then
                ParCnt_v := ParCnt_v + 1;
            end if;
            if EscErr = '1' then
                EscCnt_v := EscCnt_v + 1;
            end if;
            if DiscEvt = '1' then
                DiscCnt_v   := DiscCnt_v + 1;
                DisconnectT <= now;
            end if;
            ParityErrCnt  <= ParCnt_v;
            EscErrCnt     <= EscCnt_v;
            DisconnectCnt <= DiscCnt_v;
        end if;
    end process;

end architecture;
